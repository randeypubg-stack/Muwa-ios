"""Private durable work ledger. No sessions, passwords or presigned URLs here."""
import fcntl
import json
import os
import sqlite3
from pathlib import Path


class State:
    def __init__(self, folder: Path):
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        if folder.is_symlink():
            raise ValueError("Папка состояния не должна быть символической ссылкой.")
        os.chmod(folder, 0o700)
        self.folder = folder.resolve()
        self.lock = (self.folder / "import.lock").open("a")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            path = self.folder / "state.sqlite"
            if path.is_symlink():
                raise ValueError("Небезопасный файл состояния.")
            self.db = sqlite3.connect(path)
            os.chmod(path, 0o600)
            self.db.executescript("""
              CREATE TABLE IF NOT EXISTS items(channel TEXT NOT NULL,message INTEGER NOT NULL,payload TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',track TEXT,error TEXT,PRIMARY KEY(channel,message));
              CREATE TABLE IF NOT EXISTS cursors(channel TEXT PRIMARY KEY,message INTEGER NOT NULL);
            """)
        except BaseException:
            if hasattr(self, "db"): self.db.close()
            self.lock.close()
            raise

    def add(self, item, recheck=False):
        with self.db:
            self.db.execute("INSERT INTO items(channel,message,payload) VALUES(?,?,?) ON CONFLICT(channel,message) DO UPDATE SET payload=excluded.payload WHERE items.status<>'done'",
                            (item["channelId"], item["messageId"], json.dumps(item, ensure_ascii=False)))
            if recheck:
                self.db.execute("UPDATE items SET payload=?,status='pending',error=NULL WHERE channel=? AND message=?",
                                (json.dumps(item, ensure_ascii=False), item["channelId"], item["messageId"]))

    def pending(self, channel=None, limit=100, provider=None, include_errors=True):
        return [json.loads(r[0]) for r in self.db.execute("SELECT payload FROM items WHERE (status IN ('pending','ready') OR (? AND status='error')) AND (? IS NULL OR channel=?) AND (? IS NULL OR json_extract(payload,'$.kind')=?) ORDER BY CASE status WHEN 'pending' THEN 0 WHEN 'ready' THEN 1 ELSE 2 END,channel,message LIMIT ?",
                                                        (include_errors, channel, channel, provider, provider, limit))]

    def retry_errors(self, provider):
        with self.db:
            return self.db.execute("UPDATE items SET status='pending',error=NULL WHERE status='error' AND json_extract(payload,'$.kind')=?", (provider,)).rowcount

    def mark(self, item, status, track=None, error=None):
        with self.db:
            self.db.execute("UPDATE items SET status=?,track=?,error=? WHERE channel=? AND message=?",
                            (status, track, error, item["channelId"], item["messageId"]))

    def cursor(self, channel):
        row = self.db.execute("SELECT message FROM cursors WHERE channel=?", (channel,)).fetchone()
        return row[0] if row else 0

    def advance(self, channel, message):
        with self.db:
            self.db.execute("INSERT INTO cursors(channel,message) VALUES(?,?) ON CONFLICT(channel) DO UPDATE SET message=max(message,excluded.message)", (channel, message))

    def counts(self):
        return dict(self.db.execute("SELECT status,count(*) FROM items GROUP BY status"))

    def close(self):
        self.db.close()
        self.lock.close()
