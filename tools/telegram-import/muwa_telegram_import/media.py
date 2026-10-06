"""Bounded local media inspection; Telegram captions are not timed subtitles."""
import hashlib
import json
import math
import subprocess
from pathlib import Path, PureWindowsPath

MAX_AUDIO = 100 * 1024 * 1024
MAX_COVER = 10 * 1024 * 1024
# Demuxers may fetch nested URLs while probing, before format_name is checked.
# Accept only the containers we publish and local, non-network input protocols.
INPUT_POLICY = ["-protocol_whitelist", "file,pipe", "-format_whitelist", "mp3,wav,mov", "-max_alloc", "33554432"]


class InvalidMedia(ValueError):
    pass


def channel_id(value) -> str:
    text = str(value)
    if not text.lstrip("-").isdigit():
        raise ValueError("Нужен числовой ID Telegram-канала.")
    number = int(text)
    if number > 0:
        number = -(10**12 + number)
    if not -(2**53 - 1) <= number < -(10**12):
        raise ValueError("Некорректный ID Telegram-канала.")
    return str(number)


def local_export_file(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or PureWindowsPath(name).drive:
        raise InvalidMedia("Некорректный путь экспортированного файла.")
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise InvalidMedia("Файл отсутствует или находится вне экспорта.")
    return path


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inspect_audio(path: Path, hints: dict, language: str, cover_target: Path) -> dict:
    size = path.stat().st_size
    if not 0 < size <= MAX_AUDIO:
        raise InvalidMedia("Аудио должно быть не больше 100 МиБ.")
    try:
        process = subprocess.run(["ffprobe", "-v", "error", *INPUT_POLICY, "-show_format", "-show_streams", "-of", "json", str(path)],
                                 capture_output=True, timeout=30, check=True)
        probe = json.loads(process.stdout)
        info = probe["format"]
        streams = probe["streams"]
        duration = float(info["duration"])
    except (subprocess.SubprocessError, KeyError, ValueError) as error:
        raise InvalidMedia("Не удалось прочитать аудио.") from error
    if not math.isfinite(duration) or not 0 < duration <= 86400:
        raise InvalidMedia("Некорректная длительность аудио.")
    if not any(s.get("codec_type") == "audio" for s in streams):
        raise InvalidMedia("Файл не содержит аудио.")
    if any(s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic") for s in streams):
        raise InvalidMedia("Видео не импортируется как нашид.")
    formats = set(info.get("format_name", "").split(","))
    if "mp3" in formats:
        mime = "audio/mpeg"
    elif "wav" in formats:
        mime = "audio/wav"
    elif formats.intersection({"mov", "mp4", "m4a"}):
        mime = "audio/mp4"
    else:
        raise InvalidMedia("Поддерживаются MP3, M4A и WAV.")
    tags = {k.lower(): str(v) for k, v in info.get("tags", {}).items()}
    for stream in streams:
        if stream.get("codec_type") == "audio":
            for key, value in stream.get("tags", {}).items():
                tags.setdefault(key.lower(), str(value))
    fallback = Path(hints.get("originalName") or path.name).stem
    title = (tags.get("title") or hints.get("title") or fallback).strip()[:180]
    artist = (tags.get("artist") or tags.get("album_artist") or hints.get("performer") or "Исполнитель не указан").strip()[:180]
    if not title or not artist:
        raise InvalidMedia("Пустые метаданные аудио.")
    cover = None
    attached = next((s for s in streams if s.get("disposition", {}).get("attached_pic")), None)
    if attached and (not 0 < attached.get("width", 0) <= 8192 or not 0 < attached.get("height", 0) <= 8192 or attached["width"] * attached["height"] > 25_000_000):
        raise InvalidMedia("Обложка превышает допустимые размеры.")
    if attached:
        try:
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *INPUT_POLICY, "-i", str(path), "-map", "0:" + str(attached["index"]),
                            "-frames:v", "1", "-vf", "scale=w='min(1024,iw)':h='min(1024,ih)':force_original_aspect_ratio=decrease", str(cover_target)],
                           capture_output=True, check=True, timeout=30)
            cover_type(cover_target)
            cover = cover_target
        except (subprocess.SubprocessError, InvalidMedia):
            cover_target.unlink(missing_ok=True)
    return {"title": title, "artist": artist, "language": language, "duration": duration,
            "audioSha256": sha256(path), "audioType": mime, "audioSize": size, "cover": cover}


def cover_type(path: Path) -> str:
    if not 0 < path.stat().st_size <= MAX_COVER:
        raise InvalidMedia("Обложка должна быть не больше 10 МиБ.")
    with path.open("rb") as stream:
        head = stream.read(12)
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head.startswith(b"\xff\xd8"):
        return "image/jpeg"
    if head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        return "image/webp"
    raise InvalidMedia("Неподдерживаемая обложка.")
