#!/usr/bin/env python3
"""Owner-operated setup; secrets are entered on the VPS terminal, never in argv."""
import argparse
from contextlib import contextmanager
import getpass
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

CONFIG = Path('/etc/muwa/telegram-import.json')
STATE = Path('/var/lib/muwa-telegram-import')
SERVICE = 'muwa-telegram-import.service'
BACKEND = 'https://93.188.187.96'
EMAIL = 'randey.pubg@gmail.com'
CHANNEL = '@muwa144'
BOT_CONFIG = Path('/etc/muwa/telegram-bot.json')
BOT_STATE = Path('/var/lib/muwa-telegram-bot')
BOT_SERVICE = 'muwa-telegram-bot.service'


def setup_error_message(error):
    # Map only known exception types/statuses. Never echo SDK/server bodies,
    # entered passwords, configuration values or subprocess arguments.
    from muwa_telegram_import.api import APIError
    from muwa_telegram_import.bot import BotError
    if isinstance(error, BotError):
        hints = {401: 'Telegram отклонил токен. Проверь токен этого бота в BotFather.',
                 409: 'У бота уже работает другой получатель обновлений. Используй отдельного бота для Muwa.',
                 429: 'Telegram ограничил запросы. Подожди перед повтором.'}
        return 'Настройка не завершена: ' + hints.get(error.status, 'Telegram Bot API HTTP ' + str(error.status) + '. Проверь соединение.')
    if isinstance(error, APIError):
        hints = {
            401: 'Muwa отклонил вход (HTTP 401). Проверь пароль аккаунта randey.pubg@gmail.com в новой панели https://93.188.187.96/admin; это не пароль SSH или Telegram.',
            403: 'Muwa запретил импорт (HTTP 403). Требуются права владельца; повторный ввод Telegram-кода не поможет.',
            429: 'Muwa ограничил число попыток (HTTP 429). Подожди 15 минут перед повторным входом.',
        }
        return 'Настройка не завершена: ' + hints.get(error.status, 'Muwa API: HTTP ' + str(error.status) + '. Проверь доступность сервера.')
    return 'Настройка не завершена: ' + type(error).__name__ + '. Проверь доступ и повтори команду.'


def validate_config(value):
    if not isinstance(value, dict) or set(value) != {
        'TELEGRAM_API_ID', 'TELEGRAM_API_HASH', 'MUWA_IMPORT_BACKEND',
        'MUWA_IMPORT_EMAIL', 'MUWA_IMPORT_PASSWORD', 'MUWA_IMPORT_CHANNEL',
    }:
        raise ValueError('Неполная конфигурация импортёра.')
    if not all(isinstance(x, str) and x and '\n' not in x and '\r' not in x for x in value.values()):
        raise ValueError('Некорректные настройки импортёра.')
    if not re.fullmatch(r'[1-9]\d{0,11}', value['TELEGRAM_API_ID']) or not re.fullmatch(r'[a-fA-F0-9]{32}', value['TELEGRAM_API_HASH']):
        raise ValueError('Проверь API ID и API hash в my.telegram.org.')
    if value['MUWA_IMPORT_BACKEND'] != BACKEND or value['MUWA_IMPORT_EMAIL'] != EMAIL or value['MUWA_IMPORT_CHANNEL'] != CHANNEL:
        raise ValueError('Настройки должны соответствовать владельцу и выбранному каналу Muwa.')
    return value


def run_service():
    directory = os.environ.get('CREDENTIALS_DIRECTORY')
    if not directory:
        raise ValueError('Запускай наблюдение через systemctl start ' + SERVICE)
    values = validate_config(json.loads((Path(directory) / 'import-config').read_text()))
    os.environ.update(values)
    from muwa_telegram_import.cli import main
    main(['telegram', CHANNEL, '--backend', BACKEND, '--upload', '--watch',
          '--state-dir', str(STATE), '--language', 'und', '--batch-size', '100'])


def write_config(data, config=None):
    config = CONFIG if config is None else config
    config.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=config.parent, prefix='.telegram-config-', delete=False) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, config)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


@contextmanager
def pause_watcher(config=None, service=None):
    config, service = (CONFIG if config is None else config), (SERVICE if service is None else service)
    was_active = subprocess.run(['systemctl', 'is-active', '--quiet', service]).returncode == 0
    was_enabled = subprocess.run(['systemctl', 'is-enabled', '--quiet', service]).returncode == 0
    previous = config.read_bytes() if config.exists() else None
    if was_active:
        subprocess.run(['systemctl', 'stop', service], check=True)
    try:
        yield
    except BaseException:
        # A cancelled/failed login must not silently disable an existing import.
        # Restore the previous private credential if committing setup failed.
        subprocess.run(['systemctl', 'stop', service], check=True)
        if previous is not None:
            write_config(previous, config)
        else:
            config.unlink(missing_ok=True)
        if not was_enabled:
            subprocess.run(['systemctl', 'disable', service], check=True)
        if was_active:
            subprocess.run(['systemctl', 'start', service], check=True)
        raise


def configure(login_mode=None):
    if os.geteuid() != 0 or not sys.stdin.isatty() or not sys.stderr.isatty():
        raise ValueError('Открой эту команду в своём интерактивном Termius под root.')
    from muwa_telegram_import.api import MuwaAPI
    print('Telegram → Muwa: @muwa144. Файлы появятся черновиками в панели.')
    print('API ID и API hash возьми в my.telegram.org → API development tools.')
    values = validate_config({
        'TELEGRAM_API_ID': input('API ID: ').strip(),
        'TELEGRAM_API_HASH': getpass.getpass('API hash (скрыт): ').strip(),
        'MUWA_IMPORT_BACKEND': BACKEND,
        'MUWA_IMPORT_EMAIL': EMAIL,
        'MUWA_IMPORT_PASSWORD': getpass.getpass('Пароль твоего аккаунта Muwa (скрыт): '),
        'MUWA_IMPORT_CHANNEL': CHANNEL,
    })
    api = MuwaAPI(BACKEND)
    try:
        api.login(EMAIL, values['MUWA_IMPORT_PASSWORD'])
        # Read-only preflight verifies server ownership before Telegram login.
        api.action({'action': 'lookup-telegram-import',
                    'source': {'channelId': '-1000000012345', 'messageId': 1}})
    finally:
        api.close()
    with pause_watcher():
        environment = dict(os.environ, **values)
        # Phone, OTP and optional Telegram 2FA stay inside the user's own terminal.
        login_args = ['runuser', '-u', 'muwa-import', '--', str(Path(sys.executable)),
                      '-m', 'muwa_telegram_import', 'telegram-login', '--state-dir', str(STATE)]
        if login_mode:
            login_args.append('--' + login_mode)
        subprocess.run(login_args,
                       env=environment, check=True)
        # Confirm selected broadcast channel access without storing or importing
        # messages. A wrong/non-accessible channel cannot start the watcher.
        check = '''import asyncio, os
from muwa_telegram_import.cli import telegram_client
from muwa_telegram_import.state import State
from telethon import types
async def verify():
    state = State(os.environ['MUWA_SETUP_STATE'])
    client = None
    try:
        client = await telegram_client(state)
        entity = await client.get_entity(os.environ['MUWA_IMPORT_CHANNEL'])
        if not isinstance(entity, types.Channel) or not entity.broadcast:
            raise ValueError('Нужен доступ к выбранному каналу.')
    finally:
        if client: await client.disconnect()
        state.close()
asyncio.run(verify())
'''
        environment['MUWA_SETUP_STATE'] = str(STATE)
        subprocess.run(['runuser', '-u', 'muwa-import', '--', str(Path(sys.executable)), '-c', check],
                       env=environment, check=True)
        write_config((json.dumps(values) + '\n').encode())
        subprocess.run(['systemctl', 'enable', '--now', SERVICE], check=True)
    print('Импорт запущен. Черновики: ' + BACKEND + '/admin')
    print('Остановить: systemctl stop ' + SERVICE)
    print('Статус: systemctl status ' + SERVICE + ' --no-pager')


def validate_bot_config(value):
    from muwa_telegram_import.bot import TOKEN, positive_id
    if not isinstance(value, dict) or set(value) != {'token', 'botId', 'ownerId', 'nextOffset', 'backend', 'email', 'password'}:
        raise ValueError('Некорректные настройки бота.')
    if not isinstance(value['token'], str) or not TOKEN.fullmatch(value['token']):
        raise ValueError('Проверь токен BotFather.')
    if not positive_id(value['botId']) or not positive_id(value['ownerId']) or not positive_id(value['nextOffset'], 2147483648):
        raise ValueError('Некорректная привязка владельца.')
    if (value['backend'] != BACKEND or value['email'] != EMAIL or not isinstance(value['password'], str)
            or not value['password'] or '\n' in value['password'] or '\r' in value['password']):
        raise ValueError('Настройки должны соответствовать существующему владельцу Muwa.')
    return value


def configure_bot():
    if os.geteuid() != 0 or not sys.stdin.isatty() or not sys.stdout.isatty() or not sys.stderr.isatty():
        raise ValueError('Открой настройку бота в своём интерактивном Termius под root.')
    from muwa_telegram_import.api import MuwaAPI
    from muwa_telegram_import.bot import BotAPI, pair_owner, positive_id
    print('Muwa: личный бот для пересылки аудио. Файлы появятся черновиками в панели.')
    token = getpass.getpass('Токен нового бота из BotFather (скрыт): ').strip()
    password = getpass.getpass('Пароль аккаунта Muwa randey.pubg@gmail.com (скрыт): ')
    bot, api = BotAPI(token), MuwaAPI(BACKEND)
    try:
        api.login(EMAIL, password)
        me = bot.call('getMe')
        if (not isinstance(me, dict) or me.get('is_bot') is not True or not positive_id(me.get('id'))
                or not isinstance(me.get('username'), str) or not re.fullmatch(r'[A-Za-z0-9_]{5,32}', me['username'])):
            raise ValueError('Telegram не подтвердил бота.')
        print('Бот: @' + me['username'])
        api.action({'action': 'lookup-telegram-import', 'source': {'botId': me['id'], 'chatId': 1, 'messageId': 1}})
        webhook = bot.call('getWebhookInfo')
        if not isinstance(webhook, dict) or webhook.get('url'):
            print('У этого бота уже настроен webhook. Создай отдельного бота для Muwa.')
            raise ValueError('Нельзя заменять чужое подключение бота.')
        with pause_watcher(BOT_CONFIG, BOT_SERVICE):
            owner, offset = pair_owner(bot, me['username'])
            values = validate_bot_config({'token': token, 'botId': me['id'], 'ownerId': owner, 'nextOffset': offset,
                                          'backend': BACKEND, 'email': EMAIL, 'password': password})
            write_config((json.dumps(values) + '\n').encode(), BOT_CONFIG)
            subprocess.run(['systemctl', 'enable', '--now', BOT_SERVICE], check=True)
        bot.notify(owner, None, 'Бот Muwa привязан к тебе. Перешли нашид как MP3/M4A/WAV до 20 МБ — он появится в черновиках. /status — состояние, /retry — повторить ошибки. https://93.188.187.96/admin')
        print('Бот настроен. Принимать файлы может только твой Telegram ID.')
        print('Черновики: ' + BACKEND + '/admin')
    finally:
        bot.close()
        api.close()


def run_bot_service():
    directory = os.environ.get('CREDENTIALS_DIRECTORY')
    if not directory:
        raise ValueError('Запускай бота через systemctl start ' + BOT_SERVICE)
    from muwa_telegram_import.bot import run
    values = validate_bot_config(json.loads((Path(directory) / 'bot-config').read_text()))
    run(values, BOT_STATE)


if __name__ == '__main__':
    os.umask(0o077)
    logging.getLogger('telethon').setLevel(logging.ERROR)
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--run', action='store_true')
    mode.add_argument('--bot', action='store_true', help='Настроить личного бота для пересылки нашидов')
    mode.add_argument('--run-bot', action='store_true')
    parser.add_argument('--qr', action='store_true', help='Вход в Telegram по QR без SMS; нужен второй экран')
    args = parser.parse_args()
    if (args.run or args.bot or args.run_bot) and args.qr:
        parser.error('Подтверждение Telegram запускается вручную, без --run.')
    try:
        if args.bot:
            configure_bot()
        elif args.run_bot:
            run_bot_service()
        elif args.run:
            run_service()
        else:
            configure('qr' if args.qr else None)
    except KeyboardInterrupt:
        print('Настройка остановлена.', file=sys.stderr)
        raise SystemExit(130)
    except Exception as error:
        # Never serialize config, SDK exception bodies or process environments.
        print(setup_error_message(error), file=sys.stderr)
        raise SystemExit(1)
