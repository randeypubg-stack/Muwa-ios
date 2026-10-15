"""Read one explicit channel. Never scrape HTML or enumerate a user's dialogs."""
import json
from pathlib import Path
from .media import channel_id, local_export_file, MAX_AUDIO


def export_items(path: Path):
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("Разделите экспорт: JSON превышает 64 МиБ.")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("type") not in {"public_channel", "private_channel"}:
        raise ValueError("Нужен JSON-экспорт одного Telegram-канала.")
    channel = channel_id(data["id"])
    for message in data["messages"]:
        if message.get("type") != "message" or message.get("media_type") not in {"audio_file", "file"}:
            continue
        filename = message.get("file", "")
        if not isinstance(filename, str) or Path(filename).suffix.lower() not in {".mp3", ".m4a", ".wav"}:
            continue
        identifier = message.get("id")
        if not isinstance(identifier, int) or isinstance(identifier, bool) or not 0 < identifier <= 2147483647:
            raise ValueError("Некорректный ID сообщения.")
        # Resolve at processing time too, so a subsequently changed symlink
        # cannot turn the export into an arbitrary local-file upload.
        yield {"channelId": channel, "messageId": identifier, "kind": "export",
               "root": str(path.parent.resolve()), "file": filename,
               "thumbnail": message.get("thumbnail"),
               "originalName": Path(filename).name,
               "title": message.get("title"), "performer": message.get("performer")}


def telegram_item(channel: str, message):
    document = getattr(message, "document", None)
    file = getattr(message, "file", None)
    if not document or not file or not 0 < file.size <= MAX_AUDIO:
        return None
    mime = (file.mime_type or "").lower()
    extension = Path(getattr(file, "name", "") or "").suffix.lower()
    if mime not in {"audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/wav", "audio/x-wav"} and not (mime == "application/octet-stream" and extension in {".mp3", ".m4a", ".wav"}):
        return None
    return {"channelId": channel, "messageId": message.id, "kind": "telegram",
            "title": getattr(file, "title", None), "performer": getattr(file, "performer", None),
            "originalName": getattr(file, "name", None)}


async def download_telegram(client, channel, item: dict, folder: Path):
    message = await client.get_messages(channel, ids=item["messageId"])
    if not message or not telegram_item(item["channelId"], message):
        raise ValueError("Аудио удалено или больше не поддерживается.")
    extension = {"audio/mpeg": ".mp3", "audio/mp4": ".m4a", "audio/x-m4a": ".m4a", "audio/wav": ".wav", "audio/x-wav": ".wav"}.get((message.file.mime_type or "").lower(), Path(getattr(message.file, "name", "") or "").suffix.lower())
    path = folder / (str(item["messageId"]) + extension)
    def progress(current, total):
        if current > MAX_AUDIO or total > MAX_AUDIO:
            raise ValueError("Аудио превышает лимит.")
    try:
        saved = await client.download_media(message, file=str(path), progress_callback=progress)
        if not saved or not path.is_file() or path.stat().st_size != message.file.size:
            raise ValueError("Неполная загрузка аудио.")
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return path


def exported_audio(item: dict) -> Path:
    return local_export_file(Path(item["root"]), item["file"])
