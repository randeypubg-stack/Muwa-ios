import asyncio
import contextlib
import io
import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace
import httpx
from muwa_telegram_import.api import MuwaAPI, APIError
from muwa_telegram_import.cli import arguments, run_export
from muwa_telegram_import.media import channel_id, inspect_audio, local_export_file, InvalidMedia
from muwa_telegram_import.sources import export_items, download_telegram
from muwa_telegram_import.state import State


class OwnerSetupTests(unittest.TestCase):
    def test_setup_accepts_only_the_selected_owner_backend_and_channel(self):
        spec = importlib.util.spec_from_file_location('owner_setup', Path(__file__).resolve().parents[1] / 'setup-owner.py')
        setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(setup)
        config = {'TELEGRAM_API_ID': '12345', 'TELEGRAM_API_HASH': 'a' * 32,
                  'MUWA_IMPORT_BACKEND': setup.BACKEND, 'MUWA_IMPORT_EMAIL': setup.EMAIL,
                  'MUWA_IMPORT_PASSWORD': 'local-fixture-only', 'MUWA_IMPORT_CHANNEL': setup.CHANNEL}
        self.assertEqual(setup.validate_config(config), config)
        for key, wrong in [('TELEGRAM_API_ID', '0'), ('TELEGRAM_API_HASH', 'invalid'),
                           ('MUWA_IMPORT_CHANNEL', '@other'), ('MUWA_IMPORT_EMAIL', 'other@example.invalid'),
                           ('MUWA_IMPORT_BACKEND', 'https://other.invalid'), ('MUWA_IMPORT_PASSWORD', 'line\nbreak')]:
            with self.assertRaises(ValueError): setup.validate_config(dict(config, **{key: wrong}))
        with self.assertRaises(ValueError): setup.validate_config(dict(config, unexpected='x'))


def wav(path):
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(16000)
        stream.writeframes(b"\x00\x00" * 4800)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        wav(self.root / "نشيد.wav")
        self.export = self.root / "result.json"
        self.export.write_text(json.dumps({"id": 1234567890, "type": "public_channel", "messages": [
            {"id": 1, "type": "message", "media_type": "audio_file", "file": "نشيد.wav", "title": "عنوان", "performer": "فنان"},
            {"id": 2, "type": "message", "media_type": "photo", "file": "a.jpg"},
            {"id": 3, "type": "message", "media_type": "voice_message", "file": "voice.ogg"},
        ]}))

    def tearDown(self):
        self.temp.cleanup()

    def test_channel_identity_is_shared_by_export_and_mtproto_including_short_ids(self):
        self.assertEqual(channel_id(1234567890), "-1001234567890")
        self.assertEqual(channel_id("-1001234567890"), "-1001234567890")
        self.assertEqual(channel_id(12345), "-1000000012345")
        for value in [0, -1234, "@user", 2**53]:
            with self.assertRaises(ValueError): channel_id(value)

    def test_export_keeps_arabic_metadata_and_ignores_non_audio(self):
        items = list(export_items(self.export))
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["title"], "عنوان")
        media = inspect_audio(self.root / "نشيد.wav", items[0], "ar", self.root / "cover.jpg")
        self.assertAlmostEqual(media["duration"], .3)
        self.assertEqual(media["audioType"], "audio/wav")
        self.assertEqual(media["artist"], "فنان")
        self.assertEqual(len(media["audioSha256"]), 64)

    def test_paths_cannot_escape_export_with_parent_absolute_drive_or_symlink(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other) / "outside.wav"
            wav(outside)
            (self.root / "link.wav").symlink_to(outside)
            for name in ["../outside.wav", str(outside), "C:\\private\\secret.wav", "link.wav", "missing.wav"]:
                with self.assertRaises(InvalidMedia): local_export_file(self.root, name)

    def test_corrupt_file_and_unknown_container_are_not_ready(self):
        bad = self.root / "bad.mp3"
        bad.write_bytes(b"not audio")
        with self.assertRaises(InvalidMedia): inspect_audio(bad, {}, "und", self.root / "cover.jpg")

    def test_mp3_tags_take_precedence_and_embedded_artwork_is_extracted(self):
        logo = Path(__file__).resolve().parents[3] / "branding/AppMark.png"
        path = self.root / "tagged.mp3"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(self.root / "نشيد.wav"), "-i", str(logo),
                        "-map", "0:a", "-map", "1:v", "-c:a", "libmp3lame", "-c:v", "copy", "-id3v2_version", "3",
                        "-metadata", "title=عنوان من الملف", "-metadata", "artist=فنان من الملف", "-disposition:v", "attached_pic", str(path)],
                       check=True, capture_output=True, timeout=30)
        cover = self.root / "embedded.jpg"
        media = inspect_audio(path, {"title": "Telegram title", "performer": "Telegram artist"}, "ar", cover)
        self.assertEqual(media["title"], "عنوان من الملف")
        self.assertEqual(media["artist"], "فنان من الملف")
        self.assertEqual(media["audioType"], "audio/mpeg")
        self.assertEqual(media["cover"], cover)
        self.assertTrue(cover.read_bytes().startswith(b"\xff\xd8"))

    def test_m4a_is_supported_but_an_ordinary_video_is_not(self):
        audio = self.root / "audio.m4a"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(self.root / "نشيد.wav"), "-c:a", "aac", str(audio)],
                       check=True, capture_output=True, timeout=30)
        self.assertEqual(inspect_audio(audio, {}, "ar", self.root / "cover.jpg")["audioType"], "audio/mp4")
        video = self.root / "video.mp4"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "color=size=16x16:duration=0.3", "-i", str(self.root / "نشيد.wav"),
                        "-c:v", "mpeg4", "-c:a", "aac", "-shortest", str(video)], check=True, capture_output=True, timeout=30)
        with self.assertRaises(InvalidMedia): inspect_audio(video, {}, "ar", self.root / "cover.jpg")

    def test_preview_uses_real_ffprobe_and_makes_no_account_request(self):
        args = arguments(["export", str(self.export), "--state-dir", str(self.root / "state"), "--language", "ar"])
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(run_export(args), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["mode"], "local-preview")
        self.assertEqual(report["state"], {"ready": 1})
        state = State(self.root / "state")
        self.assertEqual(len(state.pending()), 1)
        self.assertEqual(stat.S_IMODE((state.folder / "state.sqlite").stat().st_mode), 0o600)
        state.close()

    def test_checkpoint_reopen_does_not_lose_failed_item_after_cursor_advances(self):
        item = list(export_items(self.export))[0]
        folder = self.root / "state"
        state = State(folder)
        state.add(item)
        state.advance(item["channelId"], 99)
        state.mark(item, "error", error="HTTP_503")
        state.close()
        state = State(folder)
        self.assertEqual(state.cursor(item["channelId"]), 99)
        self.assertEqual(state.pending()[0]["messageId"], 1)
        state.mark(item, "done", track="muwa-id")
        state.add(item)
        self.assertEqual(state.pending(), [])
        state.close()

    def test_partial_telegram_download_is_removed(self):
        item = {"channelId": "-1001234567890", "messageId": 1}
        class Client:
            async def get_messages(self, *args, **kwargs):
                return SimpleNamespace(id=1, document=True, file=SimpleNamespace(size=32, mime_type="audio/mpeg", title=None, performer=None, name="a.mp3"))
            async def download_media(self, message, file, **kwargs):
                Path(file).write_bytes(b"partial")
                raise OSError("connection dropped")
        with self.assertRaises(OSError): asyncio.run(download_telegram(Client(), object(), item, self.root))
        self.assertFalse((self.root / "1.mp3").exists())

    def test_a_returned_partial_telegram_file_is_also_rejected(self):
        item = {"channelId": "-1001234567890", "messageId": 1}
        class Client:
            async def get_messages(self, *args, **kwargs):
                return SimpleNamespace(id=1, document=True, file=SimpleNamespace(size=32, mime_type="audio/mpeg", title=None, performer=None, name="a.mp3"))
            async def download_media(self, message, file, **kwargs):
                Path(file).write_bytes(b"partial")
                return file
        with self.assertRaises(ValueError): asyncio.run(download_telegram(Client(), object(), item, self.root))
        self.assertFalse((self.root / "1.mp3").exists())

    def test_provider_switch_keeps_completed_identity_and_does_not_starve_new_jobs(self):
        item = list(export_items(self.export))[0]
        state = State(self.root / "state")
        state.add(item)
        state.add({**item, "kind": "telegram"})
        self.assertEqual(state.pending(provider="export"), [])
        self.assertEqual(len(state.pending(provider="telegram")), 1)
        state.mark(item, "done", track="muwa-id")
        state.add(item)
        self.assertEqual(state.pending(), [])
        state.close()


class APITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "a.wav"
        wav(self.path)
        self.item = {"channelId": "-1001234567890", "messageId": 1}
        self.media = inspect_audio(self.path, {}, "und", self.path.with_suffix(".jpg"))
        self.calls = []
        self.storage_calls = []
        self.save_calls = 0
        self.lease_calls = 0
        self.lost_ack = False

    def tearDown(self): self.temp.cleanup()

    def handler(self, req):
        body = json.loads(req.content)
        self.calls.append((req.url.path, body))
        if req.url.path.endswith("login_with_password"):
            self.assertEqual(body["json"]["password"], "local-secret")
            return httpx.Response(200, json={"json": {"user": {"role": "admin"}}}, headers={"Set-Cookie": "session=account-secret; Path=/; Secure; HttpOnly"})
        self.assertIn("account-secret", req.headers.get("cookie", ""))
        action = body["action"]
        if action == "lookup-telegram-import": return httpx.Response(200, json={"ok": True, "importStatus": "missing"})
        if action == "prepare-upload":
            self.lease_calls += 1
            return httpx.Response(200, json={"ok": True, "uploadId": "9234fbc1-c4e5-4554-a728-48ca6e0a5a97", "files": [{"part": "audio", "contentType": "audio/wav", "sizeBytes": self.path.stat().st_size, "presignedUrl": "https://muwa.invalid/put?signature=object-secret", "headers": {"Content-Type": "audio/wav", "Content-Length": str(self.path.stat().st_size), "If-None-Match": "*"}}]})
        if action == "import-telegram-track":
            self.save_calls += 1
            self.assertEqual(body["status"], "draft")
            self.assertEqual(body["source"]["audioSha256"], self.media["audioSha256"])
            if self.lost_ack and self.save_calls == 1:
                raise httpx.ReadTimeout("lost acknowledgement", request=req)
            return httpx.Response(200, json={"ok": True, "trackId": "muwa-original-id", "importStatus": "existing" if self.save_calls > 1 else "created"})
        self.fail("unexpected action")

    def store(self, req):
        self.assertNotIn("cookie", req.headers)
        self.assertNotIn("authorization", req.headers)
        self.assertEqual(req.headers["if-none-match"], "*")
        self.assertEqual(req.content, self.path.read_bytes())
        self.storage_calls.append(req)
        return httpx.Response(200)

    def api(self):
        api = MuwaAPI("https://muwa.invalid", transport=httpx.MockTransport(self.handler), storage_transport=httpx.MockTransport(self.store), sleep=lambda _: None)
        api.login("owner@example.invalid", "local-secret")
        self.addCleanup(api.close)
        return api

    def test_full_protocol_uses_existing_auth_and_streams_bytes_without_session_to_storage(self):
        result = self.api().import_audio(self.item, self.path, self.media)
        self.assertEqual(result["trackId"], "muwa-original-id")
        self.assertEqual(self.lease_calls, 1)
        self.assertEqual(len(self.storage_calls), 1)

    def test_lost_save_acknowledgement_retries_same_source_lease_and_hash(self):
        self.lost_ack = True
        result = self.api().import_audio(self.item, self.path, self.media)
        self.assertEqual(result["importStatus"], "existing")
        saves = [b for p, b in self.calls if b.get("action") == "import-telegram-track"]
        self.assertEqual(saves[0], saves[1])
        self.assertEqual(self.lease_calls, 1)

    def test_existing_source_skips_reservation_and_put(self):
        original = self.handler
        def handler(req):
            if req.url.path.endswith("admin/action") and json.loads(req.content)["action"] == "lookup-telegram-import":
                return httpx.Response(200, json={"ok": True, "trackId": "muwa-id", "importStatus": "existing"})
            return original(req)
        self.handler = handler
        self.assertEqual(self.api().import_audio(self.item, self.path, self.media)["trackId"], "muwa-id")
        self.assertEqual(self.lease_calls, 0)
        self.assertEqual(self.storage_calls, [])

    def test_refuses_insecure_credentials_urls_and_does_not_echo_storage_token(self):
        for url in ["http://muwa.invalid", "https://name:password@muwa.invalid", "https://muwa.invalid/path", "https://muwa.invalid/?secret=x"]:
            with self.assertRaises(ValueError): MuwaAPI(url)
        self.assertNotIn("object-secret", str(APIError(503)))

    def test_permission_denial_is_not_retried(self):
        counter = []
        def deny(req):
            counter.append(req)
            return httpx.Response(403)
        api = MuwaAPI("https://muwa.invalid", transport=httpx.MockTransport(deny), sleep=lambda _: self.fail("must not retry"))
        self.addCleanup(api.close)
        with self.assertRaises(APIError): api.action({"action": "lookup-telegram-import", "source": self.item}, retry=True)
        self.assertEqual(len(counter), 1)


if __name__ == "__main__": unittest.main()
