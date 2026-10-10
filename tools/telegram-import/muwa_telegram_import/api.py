"""Existing Muwa session/API and a separate, credential-free storage client."""
import time
from pathlib import Path
from urllib.parse import urlsplit
import httpx
from .media import cover_type


class APIError(RuntimeError):
    def __init__(self, status):
        self.status = status
        super().__init__(f"Muwa API: HTTP {status}; секреты и тело ответа не записываются в журнал.")


def https_url(value: str) -> str:
    url = urlsplit(value)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError("Нужен HTTPS-адрес без логина и пароля в URL.")
    return value


class MuwaAPI:
    def __init__(self, base: str, transport=None, storage_transport=None, sleep=time.sleep):
        https_url(base)
        if urlsplit(base).path not in {"", "/"} or urlsplit(base).query:
            raise ValueError("Укажите только origin backend, без пути и query.")
        self.http = httpx.Client(base_url=base, transport=transport, timeout=120, follow_redirects=False)
        # Never pass the session jar, account credentials or auth headers to a
        # signed storage URL, including a URL hosted on the same domain.
        self.storage = httpx.Client(transport=storage_transport, timeout=180, follow_redirects=False)
        self.sleep = sleep

    def login(self, email, password):
        response = self.http.post("/_api/auth/login_with_password", json={"json": {"email": email, "password": password}})
        if not response.is_success:
            raise APIError(response.status_code)
        user = response.json().get("json", {}).get("user", {})
        if user.get("role") != "admin":
            raise APIError(403)

    def action(self, body, retry=False):
        for attempt in range(3 if retry else 1):
            try:
                response = self.http.post("/_api/admin/action", json=body)
            except httpx.TransportError:
                if retry and attempt < 2:
                    self.sleep(2 ** attempt)
                    continue
                raise APIError(503) from None
            if retry and (response.status_code == 429 or response.status_code >= 500) and attempt < 2:
                self.sleep(60 if response.status_code == 429 else 2 ** attempt)
                continue
            if not response.is_success:
                raise APIError(response.status_code)
            result = response.json()
            if result.get("ok") is not True:
                raise APIError(502)
            return result
        raise APIError(503)

    def import_audio(self, item: dict, path: Path, media: dict, cover: Path | None = None):
        identity = {"botId": item["botId"], "chatId": item["chatId"]} if item.get("kind") == "bot" else {"channelId": item["channelId"]}
        source = {**identity, "messageId": item["messageId"], "audioSha256": media["audioSha256"]}
        found = self.action({"action": "lookup-telegram-import", "source": source}, retry=True)
        if found.get("trackId"):
            return found
        self.sleep(1.1)
        files = {"audio": (path, media["audioType"])}
        if cover:
            files["cover"] = (cover, cover_type(cover))
        plan = self.action({"action": "prepare-upload", "files": [{"part": part, "contentType": mime, "sizeBytes": file.stat().st_size} for part, (file, mime) in files.items()]})
        if not plan.get("uploadId") or {f["part"] for f in plan.get("files", [])} != set(files):
            raise APIError(502)
        for f in plan["files"]:
            target = https_url(f["presignedUrl"])
            local, mime = files[f["part"]]
            if f["sizeBytes"] != local.stat().st_size or f["contentType"] != mime:
                raise APIError(502)
            with local.open("rb") as stream:
                try:
                    response = self.storage.put(target, content=iter(lambda: stream.read(1024 * 1024), b""), headers=f["headers"])
                except httpx.TransportError:
                    raise APIError(503) from None
            if not response.is_success:
                raise APIError(response.status_code)
        self.sleep(1.1)
        return self.action({"action": "import-telegram-track", "source": source, "uploadId": plan["uploadId"],
                            **{k: media[k] for k in ["title", "artist", "language", "duration"]}, "status": "draft"}, retry=True)

    def close(self):
        self.http.close()
        self.storage.close()
