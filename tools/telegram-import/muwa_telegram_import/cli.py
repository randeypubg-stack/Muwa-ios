"""Preview by default; actual uploads require an explicit flag and admin login."""
import argparse
import asyncio
import getpass
import json
import logging
import os
import re
import sys
import time
from pathlib import Path
from .api import MuwaAPI, APIError
from .media import InvalidMedia, channel_id, inspect_audio, local_export_file, cover_type
from .sources import export_items, telegram_item, download_telegram, exported_audio
from .state import State


def arguments(argv=None):
    parser = argparse.ArgumentParser(description="Telegram → существующий каталог Muwa; импорт всегда создаёт черновики.")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--state-dir", type=Path, default=Path(".muwa-telegram"))
    common.add_argument("--backend", default=os.environ.get("MUWA_IMPORT_BACKEND"))
    common.add_argument("--language", default="und", help="Код языка вручную; und означает не определён")
    common.add_argument("--upload", action="store_true", help="Загрузить в Muwa; без флага только локальная проверка")
    common.add_argument("--batch-size", type=int, default=100)
    common.add_argument("--interval", type=float, default=20, help="Пауза между файлами; минимум 20 секунд сохраняет upload-квоты")
    commands = parser.add_subparsers(dest="command", required=True)
    archive = commands.add_parser("export", parents=[common])
    archive.add_argument("json_file", type=Path, help="result.json из экспорта одного канала Telegram Desktop")
    archive.add_argument("--recheck", action="store_true", help="Повторно проверить байты уже импортированных сообщений; не перезаписывает их")
    live = commands.add_parser("telegram", parents=[common])
    live.add_argument("channel", help="Явно выбранный @username или числовой peer ID канала")
    live.add_argument("--watch", action="store_true", help="После истории следить за новыми сообщениями")
    live.add_argument("--scan-limit", type=int, default=500, help="Число сообщений на цикл, включая неаудио")
    login = commands.add_parser("telegram-login")
    login.add_argument("--state-dir", type=Path, default=Path(".muwa-telegram"))
    args = parser.parse_args(argv)
    if args.command != "telegram-login":
        if not re.fullmatch(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,6})?", args.language) or len(args.language) > 10:
            parser.error("Некорректный код языка.")
        if not 1 <= args.batch_size <= 1000 or not 20 <= args.interval <= 3600:
            parser.error("batch-size 1–1000; interval 20–3600 секунд.")
        if args.upload and not args.backend:
            parser.error("Для загрузки нужен --backend.")
        if args.command == "telegram":
            if not 1 <= args.scan_limit <= 5000:
                parser.error("scan-limit 1–5000 сообщений.")
            if args.watch and not args.upload:
                parser.error("watch требует --upload; одиночный запуск без флага делает локальный preview.")
    return args


def admin_api(args):
    api = MuwaAPI(args.backend)
    email = os.environ.get("MUWA_IMPORT_EMAIL") or input("Email существующего администратора Muwa: ")
    password = os.environ.get("MUWA_IMPORT_PASSWORD") or getpass.getpass("Пароль Muwa (ввод скрыт): ")
    try:
        api.login(email, password)
    except BaseException:
        api.close()
        raise
    return api


def inspect_item(state: State, item: dict, path: Path, language: str):
    folder = state.folder / "media" / item["channelId"].lstrip("-")
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    media = inspect_audio(path, item, language, folder / (str(item["messageId"]) + "-cover.jpg"))
    cover = media["cover"]
    if not cover and item.get("thumbnail") and item["kind"] == "export":
        try:
            cover = local_export_file(Path(item["root"]), item["thumbnail"])
            cover_type(cover)
        except InvalidMedia:
            cover = None
    return media, cover


def finish_item(state, item, path, media, cover, api):
    if api:
        result = api.import_audio(item, path, media, cover)
        if not result.get("trackId"):
            raise APIError(502)
        state.mark(item, "done", track=result["trackId"])
        return result["importStatus"]
    state.mark(item, "ready")
    return "preview"


def handle_error(state, item, error):
    # Never store exception text: SDK/HTTP exceptions may contain signed URLs,
    # credentials, local paths or a Telegram account phone number.
    code = "HTTP_" + str(error.status) if isinstance(error, APIError) else type(error).__name__
    state.mark(item, "error", error=code)
    print(json.dumps({"messageId": item["messageId"], "error": code}), file=sys.stderr)
    if isinstance(error, APIError) and error.status in {401, 403}:
        raise error


def summary(state, processed, upload):
    print(json.dumps({"mode": "upload-drafts" if upload else "local-preview", "processed": processed, "state": state.counts()}, ensure_ascii=False))


def run_export(args):
    state = State(args.state_dir)
    api = None
    processed = 0
    try:
        for item in export_items(args.json_file):
            state.add(item, recheck=args.recheck)
        if args.upload:
            api = admin_api(args)
            first = state.pending(limit=1, provider="export")
            if first:
                api.action({"action": "lookup-telegram-import", "source": {k: first[0][k] for k in ["channelId", "messageId"]}}, retry=True)
        for item in state.pending(limit=args.batch_size, provider="export"):
            try:
                path = exported_audio(item)
                media, cover = inspect_item(state, item, path, args.language)
                finish_item(state, item, path, media, cover, api)
                processed += 1
            except (ValueError, OSError, APIError) as error:
                handle_error(state, item, error)
            if api:
                time.sleep(args.interval)
        summary(state, processed, args.upload)
        return 1 if state.counts().get("error") else 0
    finally:
        if api:
            api.close()
        state.close()


async def telegram_client(state):
    from telethon import TelegramClient
    identifier = int(os.environ.get("TELEGRAM_API_ID", "0"))
    secret = os.environ.get("TELEGRAM_API_HASH", "")
    if identifier <= 0 or not re.fullmatch(r"[a-fA-F0-9]{32}", secret):
        raise ValueError("Настройте TELEGRAM_API_ID и TELEGRAM_API_HASH на сервере; не отправляйте их в чат.")
    session = state.folder / "telegram.session"
    if session.is_symlink():
        raise ValueError("Небезопасный файл Telegram-сессии.")
    if session.exists():
        os.chmod(session, 0o600)
    client = TelegramClient(str(session), identifier, secret, flood_sleep_threshold=60)
    await client.connect()
    if session.exists():
        os.chmod(session, 0o600)
    return client


async def run_telegram(args):
    from telethon import types, utils, errors
    state = State(args.state_dir)
    client = None
    api = None
    try:
        client = await telegram_client(state)
        if args.command == "telegram-login":
            # Telegram's OTP/2FA prompts stay in the operator's local terminal.
            await client.start()
            print("Telegram-сессия сохранена локально с правами 0600.")
            return 0
        if not await client.is_user_authorized():
            raise ValueError("Сначала выполните telegram-login в своём терминале.")
        entity = await client.get_entity(int(args.channel) if args.channel.lstrip("-").isdigit() else args.channel)
        if not isinstance(entity, types.Channel) or not entity.broadcast:
            raise ValueError("Выберите один канал, не личную переписку или группу.")
        channel = channel_id(utils.get_peer_id(entity))
        if args.upload:
            api = await asyncio.to_thread(admin_api, args)
            # Verify migration/API availability before downloading any media.
            await asyncio.to_thread(api.action, {"action": "lookup-telegram-import", "source": {"channelId": channel, "messageId": 1}}, True)
        while True:
            # Each queued item is committed before the bookmark advances.
            # A crash during download leaves it retryable, even if later
            # messages have already advanced the scan bookmark.
            try:
                async for message in client.iter_messages(entity, reverse=True, min_id=state.cursor(channel), limit=args.scan_limit):
                    item = telegram_item(channel, message)
                    if item:
                        state.add(item)
                    state.advance(channel, message.id)
            except errors.FloodWaitError as error:
                if not args.watch:
                    raise
                await asyncio.sleep(min(error.seconds, 3600))
                continue
            processed = 0
            for item in state.pending(channel, limit=args.batch_size, provider="telegram"):
                path = None
                cover = None
                try:
                    folder = state.folder / "media" / channel.lstrip("-")
                    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
                    path = await download_telegram(client, entity, item, folder)
                    # Keep Telegram's connection/heartbeat responsive during
                    # ffprobe and synchronous HTTPS storage/API operations.
                    media, cover = await asyncio.to_thread(inspect_item, state, item, path, args.language)
                    if api:
                        result = await asyncio.to_thread(api.import_audio, item, path, media, cover)
                        if not result.get("trackId"):
                            raise APIError(502)
                        state.mark(item, "done", track=result["trackId"])
                    else:
                        state.mark(item, "ready")
                    processed += 1
                except errors.FloodWaitError as error:
                    state.mark(item, "error", error="TelegramFloodWait")
                    await asyncio.sleep(min(error.seconds, 3600))
                    break
                except (ValueError, OSError, APIError) as error:
                    handle_error(state, item, error)
                finally:
                    # A failed batch must not fill the small VPS with complete
                    # downloads. The durable source identity makes re-download
                    # safe; the catalogue stores the actual media separately.
                    if api:
                        if path:
                            path.unlink(missing_ok=True)
                        if cover and cover.is_relative_to(state.folder):
                            cover.unlink(missing_ok=True)
                if api:
                    await asyncio.sleep(args.interval)
            summary(state, processed, args.upload)
            if not args.watch:
                return 1 if state.counts().get("error") else 0
            await asyncio.sleep(60)
    finally:
        if client:
            await client.disconnect()
        if api:
            api.close()
        state.close()


def main(argv=None):
    os.umask(0o077)
    logging.getLogger("telethon").setLevel(logging.ERROR)
    args = arguments(argv)
    try:
        status = run_export(args) if args.command == "export" else asyncio.run(run_telegram(args))
    except KeyboardInterrupt:
        status = 130
    except (ValueError, OSError, APIError) as error:
        print("Импорт остановлен: " + ("HTTP_" + str(error.status) if isinstance(error, APIError) else type(error).__name__) + ". Проверьте настройку; секреты в журнал не записаны.", file=sys.stderr)
        status = 1
    except Exception as error:
        # In particular, an SDK RPC exception must not dump its request,
        # account phone number or a signed URL through a traceback.
        print("Импорт остановлен: " + type(error).__name__ + ". Секреты и запрос в журнал не записаны.", file=sys.stderr)
        status = 1
    raise SystemExit(status)
