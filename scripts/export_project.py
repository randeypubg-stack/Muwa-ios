#!/usr/bin/env python3
"""Export a clean Muwa commit, offline Git history and assembled iOS sources."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

CHUNK_SIZE = 1024 * 1024
CACHE_DIRECTORIES = {".git", "node_modules", "__pycache__", ".venv", "venv", ".gradle", ".kotlin", "xcuserdata"}
SECRET_PATTERNS = (".env", ".env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.jks", "*.mobileprovision", "*.session", "*.session-*", "credentials*.json", "secrets*.json", "auth.json", "cookies.json", ".npmrc", ".netrc", "id_rsa*", "id_ed25519*")


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
            result.update(chunk)
    return result.hexdigest()


def command(args: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f"Command failed ({args[0]}): {result.stderr.strip()[-3000:]}")
    return result.stdout.strip()


def git_environment() -> dict[str, str]:
    env = os.environ.copy()
    env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"})
    return env


def git(repo: Path, *args: str) -> str:
    return command(["git", "-c", "core.fsmonitor=false", "-C", str(repo), *args], env=git_environment())


def safe_path(value: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value or "\0" in value or ":" in value:
        raise ValueError(f"Unsafe archive path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in value.split("/")):
        raise ValueError(f"Unsafe archive path: {value!r}")
    return path


def forbidden(path: PurePosixPath) -> bool:
    if any(part.lower() in CACHE_DIRECTORIES for part in path.parts):
        return True
    name = path.name.lower()
    if name == ".env.example":
        return False
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in SECRET_PATTERNS)


def unpack_git_archive(repo: Path, commit: str, destination: Path) -> None:
    """Extract only canonical regular Git blobs; never follow a tracked symlink."""
    destination.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryFile() as stream:
        subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(repo), "archive", "--format=tar", commit], env=git_environment(), stdout=stream, check=True)
        stream.seek(0)
        with tarfile.open(fileobj=stream, mode="r|") as archive:
            for member in archive:
                relative = safe_path(member.name.rstrip("/"))
                if member.isdir():
                    (destination / str(relative)).mkdir(parents=True, exist_ok=True)
                    continue
                if not member.isfile() or forbidden(relative):
                    raise ValueError(f"Source contains a link, cache or private file: {relative}")
                target = destination / str(relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise ValueError(f"Unreadable Git blob: {relative}")
                with source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, CHUNK_SIZE)
                target.chmod(0o755 if member.mode & 0o111 else 0o644)


def copy_optional(source: Path, target: Path) -> list[str]:
    """Copy curated documentation/evidence; omit private files and dependency caches."""
    if source.is_symlink() or not source.is_dir():
        raise ValueError(f"Optional input must be a real directory: {source}")
    target.mkdir(parents=True, exist_ok=False)
    omitted: list[str] = []
    for current, directories, files in os.walk(source, followlinks=False):
        folder = Path(current)
        relative_folder = folder.relative_to(source)
        for name in list(directories):
            candidate = folder / name
            relative = PurePosixPath((relative_folder / name).as_posix())
            safe_path(str(relative))
            if candidate.is_symlink():
                raise ValueError(f"Optional input contains a symlink: {relative}")
            if forbidden(relative):
                omitted.append(str(relative) + "/")
                directories.remove(name)
        for name in files:
            candidate = folder / name
            relative = safe_path((relative_folder / name).as_posix())
            if candidate.is_symlink() or not candidate.is_file():
                raise ValueError(f"Optional input contains a non-regular file: {relative}")
            if forbidden(relative):
                omitted.append(str(relative))
                continue
            destination = target / str(relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(candidate, destination)
            destination.chmod(0o755 if candidate.stat().st_mode & 0o111 else 0o644)
    return omitted


def inventory(root: Path) -> list[dict[str, object]]:
    files: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Export contains a symlink: {path.relative_to(root)}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"Export contains a non-regular file: {path.relative_to(root)}")
        relative = safe_path(path.relative_to(root).as_posix())
        if forbidden(relative):
            raise ValueError(f"Export contains a private file or cache: {relative}")
        files.append({"path": str(relative), "sizeBytes": path.stat().st_size, "sha256": digest(path), "mode": "0755" if path.stat().st_mode & 0o111 else "0644"})
    return files


def assemble(repository: Path, output: Path, commit: str) -> None:
    script = repository / "scripts/assemble_ios.py"
    if not script.is_file():
        raise ValueError("The committed repository has no scripts/assemble_ios.py")
    env = os.environ.copy()
    env["MUWA_SOURCE_COMMIT"] = commit
    command([sys.executable, str(script), "--output", str(output)], cwd=repository, env=env)
    if not output.is_dir():
        raise ValueError("iOS assembler did not produce its requested directory")


def start_here(commit: str, branch: str) -> str:
    return f"""# Muwa — переносимый проект

Снимок исходников: `{commit}`. Ветка: `{branch}`.

## Как продолжить в Codex

1. Сохраните этот ZIP в приложении «Файлы» на телефоне. Не удаляйте оригинал.
2. При следующей работе прикрепите ZIP к Codex и напишите:
   «Распакуй проект Muwa. Прочитай START-HERE.md, Repository/AGENTS.md,
   Repository/docs/ARCHITECTURE.md и материалы Handoff. Продолжай существующий
   проект, сохрани утверждённое положение навигации и приватность черновиков».
3. Рабочие исходники находятся в `Repository/`. Разделы кода и команды сборки
   описаны в README и docs этого каталога.

## Что находится внутри

- `Repository/` — точные файлы указанного Git-коммита: Android, iOS patches,
  backend, панель владельца, серверные инструменты, тесты и документация.
- `iOS/MuwaNasheedsNative/` — полный собранный из этих исходников Xcode-проект
  Build 53. Это исходники, а не новая подписанная версия приложения.
- `History/muwa.bundle` — автономная история текущей ветки, без Git config,
  паролей и настроек подключений. Восстановление Git-репозитория:
  `git clone --branch {branch} History/muwa.bundle Muwa-Restored`.
- `Handoff/`, `Verification/`, `DesignReferences/` — дополнительные материалы,
  если они переданы при экспорте. Референсы не заменяют исходники приложения.
- `MANIFEST.json` — список размеров и SHA-256 всех файлов архива.

Проверить архив на компьютере:
`python3 Repository/scripts/verify_project_archive.py /путь/к/архиву.zip`.
Проверка сверяет ZIP и контрольные суммы, восстанавливает Git offline,
сравнивает исходники и повторно собирает iOS-проект из Repository.

## Что нужно сохранить отдельно

Этот архив не содержит живую PostgreSQL-базу, нашиды с VPS, Telegram-сессии,
API-токены, SSH-ключи, пароли и материалы подписи приложений. Они не нужны для
чтения и продолжения кода, но для восстановления сервера потребуются отдельно
сохранённые приватные резервные копии и доступы. Существующий сервер продолжает
работать независимо от этого ZIP. Не вставляйте секреты в публичный репозиторий.
"""


def export(args: argparse.Namespace) -> dict[str, object]:
    repo = args.repository.resolve()
    if not args.output.is_absolute():
        raise ValueError("--output must be an absolute ZIP path")
    output = args.output.resolve()
    if output.suffix.lower() != ".zip":
        raise ValueError("--output must end with .zip")
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
        raise ValueError("Source is not clean. Commit tracked edits and non-ignored source files before exporting; ignored caches are excluded.")
    branch = git(repo, "symbolic-ref", "--short", "HEAD")
    commit = git(repo, "rev-parse", "HEAD")
    tree = git(repo, "rev-parse", "HEAD^{tree}")
    now = datetime.now(timezone.utc)
    root_name = "Muwa-Project-" + now.strftime("%Y-%m-%d")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output: Path | None = None
    try:
        with tempfile.TemporaryDirectory(prefix="muwa-export-") as temporary:
            stage = Path(temporary) / root_name
            stage.mkdir()
            unpack_git_archive(repo, commit, stage / "Repository")
            history = stage / "History"
            history.mkdir()
            bundle = history / "muwa.bundle"
            git(repo, "bundle", "create", str(bundle), "refs/heads/" + branch)
            heads = git(repo, "bundle", "list-heads", str(bundle)).splitlines()
            if heads != [commit + " refs/heads/" + branch]:
                raise ValueError("Bundle must contain exactly the current branch head")
            assemble(stage / "Repository", stage / "iOS/MuwaNasheedsNative", commit)
            omitted: dict[str, list[str]] = {}
            for argument, directory in (("handoff", "Handoff"), ("verification", "Verification"), ("references", "DesignReferences")):
                source = getattr(args, argument)
                if source is not None:
                    omitted[directory] = copy_optional(source, stage / directory)
            (stage / "START-HERE.md").write_text(start_here(commit, branch), encoding="utf-8", newline="\n")
            payload = inventory(stage)
            manifest = {"version": 1, "rootDirectory": root_name, "createdAt": now.isoformat(), "source": {"commit": commit, "tree": tree, "branch": branch}, "bundleHead": {"commit": commit, "ref": "refs/heads/" + branch}, "iOS": {"path": "iOS/MuwaNasheedsNative", "build": 53, "kind": "assembled source"}, "exclusions": {"optionalPaths": omitted, "liveDatabaseAndMedia": True, "credentialsAndSessionFiles": True}, "files": payload}
            (stage / "MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
            if git(repo, "rev-parse", "HEAD") != commit or git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
                raise ValueError("Source changed while exporting; repeat after changes are committed")
            handle, name = tempfile.mkstemp(prefix=output.stem + "-", suffix=".zip.tmp", dir=output.parent)
            os.close(handle)
            temporary_output = Path(name)
            with zipfile.ZipFile(temporary_output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
                for path in sorted(stage.rglob("*")):
                    if path.is_file():
                        archive.write(path, root_name + "/" + path.relative_to(stage).as_posix())
            temporary_output.chmod(0o644)
            temporary_output.replace(output)
            temporary_output = None
        return {"archive": str(output), "sizeBytes": output.stat().st_size, "sha256": digest(output), "sourceCommit": commit, "files": len(payload) + 1}
    finally:
        if temporary_output is not None:
            temporary_output.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    for name in ("handoff", "verification", "references"):
        parser.add_argument("--" + name, type=Path)
    args = parser.parse_args()
    try:
        result = export(args)
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, tarfile.TarError) as error:
        parser.exit(1, "Export failed: " + str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
