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


def write_config(data):
    CONFIG.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=CONFIG.parent, prefix='.telegram-config-', delete=False) as stream:
            temporary = Path(stream.name)
            os.chmod(temporary, 0o600)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, CONFIG)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


@contextmanager
def pause_watcher():
    was_active = subprocess.run(['systemctl', 'is-active', '--quiet', SERVICE]).returncode == 0
    was_enabled = subprocess.run(['systemctl', 'is-enabled', '--quiet', SERVICE]).returncode == 0
    previous = CONFIG.read_bytes() if CONFIG.exists() else None
    if was_active:
        subprocess.run(['systemctl', 'stop', SERVICE], check=True)
    try:
        yield
    except BaseException:
        # A cancelled/failed login must not silently disable an existing import.
        # Restore the previous private credential if committing setup failed.
        subprocess.run(['systemctl', 'stop', SERVICE], check=True)
        if previous is not None:
            write_config(previous)
        else:
            CONFIG.unlink(missing_ok=True)
        if not was_enabled:
            subprocess.run(['systemctl', 'disable', SERVICE], check=True)
        if was_active:
            subprocess.run(['systemctl', 'start', SERVICE], check=True)
        raise


def configure():
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
        subprocess.run(['runuser', '-u', 'muwa-import', '--', str(Path(sys.executable)),
                        '-m', 'muwa_telegram_import', 'telegram-login', '--state-dir', str(STATE)],
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


if __name__ == '__main__':
    os.umask(0o077)
    logging.getLogger('telethon').setLevel(logging.ERROR)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    try:
        run_service() if args.run else configure()
    except Exception as error:
        # Never serialize config, SDK exception bodies or process environments.
        print('Настройка не завершена: ' + type(error).__name__ + '. Проверь доступ и повтори команду.', file=sys.stderr)
        raise SystemExit(1)
