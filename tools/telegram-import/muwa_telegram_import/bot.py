"""Owner-only Bot API forwarding, using the existing Muwa upload pipeline."""
import json
import logging
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import tempfile
import time

import httpx

from .api import APIError, MuwaAPI
from .media import InvalidMedia, inspect_audio
from .state import State

MAX_BOT_AUDIO = 20 * 1024 * 1024  # Hosted Telegram Bot API getFile limit.
MAX_SAFE_ID = 9007199254740991
TOKEN = re.compile(r'[1-9][0-9]{4,15}:[A-Za-z0-9_-]{30,100}')
EXTENSIONS = {'.mp3', '.m4a', '.wav'}
MIME_EXTENSIONS = {'audio/mpeg': '.mp3', 'audio/mp4': '.m4a', 'audio/x-m4a': '.m4a',
                   'audio/wav': '.wav', 'audio/x-wav': '.wav'}


class BotError(RuntimeError):
    def __init__(self, status, retry_after=30):
        self.status = status
        self.retry_after = min(max(retry_after, 1), 3600)
        super().__init__('Telegram Bot API HTTP_' + str(status))


def positive_id(value, maximum=MAX_SAFE_ID):
    return isinstance(value, int) and not isinstance(value, bool) and 0 < value <= maximum


def update_id(value):
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 2147483647


class BotAPI:
    def __init__(self, token, transport=None):
        if not isinstance(token, str) or not TOKEN.fullmatch(token):
            raise ValueError('Некорректный токен BotFather.')
        self._token = token
        self.http = httpx.Client(transport=transport, timeout=httpx.Timeout(40, connect=15),
                                 follow_redirects=False, trust_env=False)

    def call(self, method, body=None):
        if method not in {'getMe', 'getWebhookInfo', 'getUpdates', 'getFile', 'sendMessage'}:
            raise ValueError('Неподдерживаемый метод Bot API.')
        try:
            with self.http.stream('POST', 'https://api.telegram.org/bot' + self._token + '/' + method,
                                  json=body or {}) as response:
                data = bytearray()
                for chunk in response.iter_bytes(65536):
                    data.extend(chunk)
                    if len(data) > 2 * 1024 * 1024:
                        raise BotError(502)
                try:
                    result = json.loads(data)
                except (ValueError, UnicodeError):
                    raise BotError(502) from None
                if not isinstance(result, dict):
                    raise BotError(502)
                if not response.is_success or result.get('ok') is not True:
                    parameters = result.get('parameters')
                    retry = parameters.get('retry_after') if isinstance(parameters, dict) else None
                    status = result.get('error_code', response.status_code)
                    raise BotError(status if isinstance(status, int) else 502,
                                   retry if positive_id(retry, 3600) else 30)
                return result.get('result')
        except httpx.TransportError:
            raise BotError(503) from None

    def updates(self, offset, timeout=20):
        rows = self.call('getUpdates', {'offset': offset, 'timeout': timeout, 'limit': 100,
                                        'allowed_updates': ['message']})
        if not isinstance(rows, list):
            raise BotError(502)
        return rows

    def notify(self, owner, message, text):
        # The caller has already checked the actual sender AND private chat.
        body = {'chat_id': owner, 'text': text[:2000]}
        if message:
            body['reply_parameters'] = {'message_id': message, 'allow_sending_without_reply': True}
        try:
            self.call('sendMessage', body)
        except BotError as error:
            print('bot_notification: HTTP_' + str(error.status), flush=True)

    def download(self, item, target):
        info = self.call('getFile', {'file_id': item['fileId']})
        if not isinstance(info, dict):
            raise BotError(502)
        path = info.get('file_path')
        if (not isinstance(path, str) or not re.fullmatch(r'[A-Za-z0-9_./-]{1,512}', path)
                or path.startswith('/') or any(x in {'', '.', '..'} for x in path.split('/'))):
            raise BotError(502)
        if info.get('file_size') is not None and info['file_size'] != item['sizeBytes']:
            raise InvalidMedia('Размер Telegram-файла изменился.')
        deadline = time.monotonic() + 180
        size = 0
        try:
            with self.http.stream('GET', 'https://api.telegram.org/file/bot' + self._token + '/' + path) as response:
                if not response.is_success:
                    raise BotError(response.status_code)
                with target.open('xb') as stream:
                    for chunk in response.iter_bytes(1024 * 1024):
                        size += len(chunk)
                        if size > MAX_BOT_AUDIO or size > item['sizeBytes'] or time.monotonic() > deadline:
                            raise InvalidMedia('Аудио превышает лимит или время загрузки.')
                        stream.write(chunk)
            if size != item['sizeBytes']:
                raise InvalidMedia('Неполная загрузка Telegram-файла.')
        except httpx.TransportError:
            target.unlink(missing_ok=True)
            raise BotError(503) from None
        except BaseException:
            target.unlink(missing_ok=True)
            raise

    def close(self):
        self.http.close()


def owner_message(update, owner):
    if not isinstance(update, dict):
        return None
    message = update.get('message')
    if not isinstance(message, dict):
        return None
    sender, chat = message.get('from'), message.get('chat')
    if (not isinstance(sender, dict) or not isinstance(chat, dict) or sender.get('is_bot')
            or not positive_id(sender.get('id')) or not positive_id(chat.get('id'))
            or sender.get('id') != owner or chat.get('id') != owner or chat.get('type') != 'private'
            or not positive_id(message.get('message_id'), 2147483647)):
        return None
    return message


def audio_item(message, bot_id, owner):
    audio = message.get('audio') or message.get('document')
    if not isinstance(audio, dict):
        raise InvalidMedia('Перешли MP3, M4A или WAV как аудио или файл.')
    if not positive_id(audio.get('file_size'), MAX_BOT_AUDIO):
        raise InvalidMedia('Для пересылки боту нужен файл до 20 МБ. Большие файлы загружай через панель Muwa.')
    name = audio.get('file_name')
    extension = PurePosixPath(name).suffix.lower() if isinstance(name, str) else ''
    if extension not in EXTENSIONS:
        extension = MIME_EXTENSIONS.get(audio.get('mime_type')) if message.get('audio') else None
    file_id = audio.get('file_id')
    if not extension or not isinstance(file_id, str) or not 1 <= len(file_id) <= 512:
        raise InvalidMedia('Поддерживаются MP3, M4A и WAV.')
    hints = {key: audio[field][:180] for key, field in [('title', 'title'), ('performer', 'performer')]
             if isinstance(audio.get(field), str)}
    return {'kind': 'bot', 'botId': bot_id, 'chatId': owner,
            'channelId': f'bot:{bot_id}:{owner}', 'messageId': message['message_id'],
            'fileId': file_id, 'sizeBytes': audio['file_size'], 'extension': extension,
            'originalName': name[:180] if isinstance(name, str) else 'Нашид' + extension, **hints}


def pair_owner(bot, username, seconds=300):
    nonce = secrets.token_urlsafe(24)
    print('Открой ссылку на своём телефоне и нажми «Запустить» в Telegram:')
    print('https://t.me/' + username + '?start=' + nonce, flush=True)
    print('Ссылка привязывает бота к твоему Telegram ID. Не пересылай её.', flush=True)
    offset, deadline = 0, time.monotonic() + seconds
    while time.monotonic() < deadline:
        for update in bot.updates(offset):
            identifier = update.get('update_id') if isinstance(update, dict) else None
            if not update_id(identifier):
                continue
            message = update.get('message', {})
            sender = message.get('from', {}) if isinstance(message, dict) else {}
            owner = sender.get('id') if isinstance(sender, dict) else None
            approved = owner_message(update, owner) if positive_id(owner) else None
            if approved and approved.get('text') == '/start ' + nonce:
                return owner, identifier + 1
            offset = max(offset, identifier + 1)
    raise ValueError('Время привязки истекло. Повтори настройку.')


def enqueue(state, bot, config, update):
    owner, bot_id = config['ownerId'], config['botId']
    message = owner_message(update, owner)
    if not message:
        return
    identifier = message['message_id']
    command = message.get('text', '').split()[0] if isinstance(message.get('text'), str) and message['text'].strip() else ''
    if command in {'/start', '/help'}:
        bot.notify(owner, identifier, 'Перешли мне нашид как аудио или MP3/M4A/WAV до 20 МБ. Я сохраню его в черновики Muwa. /status — очередь, /retry — повторить ошибки. Публикация: https://93.188.187.96/admin')
        return
    if command == '/status':
        bot.notify(owner, identifier, 'Очередь импорта: ' + json.dumps(state.counts(), ensure_ascii=False))
        return
    if command == '/retry':
        count = state.retry_errors('bot')
        bot.notify(owner, identifier, 'Поставлено на повтор: ' + str(count))
        return
    try:
        item = audio_item(message, bot_id, owner)
        pending = state.db.execute("SELECT count(*) FROM items WHERE channel=? AND status IN ('pending','ready')", (item['channelId'],)).fetchone()[0]
        if pending >= 1000:
            raise InvalidMedia('Очередь заполнена. Дождись обработки и перешли файл заново.')
        state.add(item)
    except InvalidMedia as error:
        # Only our fixed validation messages, never Telegram SDK/API bodies.
        bot.notify(owner, identifier, str(error))


def process_next(state, bot, api, config):
    channel = f"bot:{config['botId']}:{config['ownerId']}"
    items = state.pending(channel, limit=1, provider='bot', include_errors=False)
    if not items:
        return False
    item = items[0]
    try:
        found = api.action({'action': 'lookup-telegram-import', 'source': {
            'botId': item['botId'], 'chatId': item['chatId'], 'messageId': item['messageId']}}, retry=True)
        if found.get('trackId'):
            result = found
        else:
            if shutil.disk_usage(state.folder).free < item['sizeBytes'] * 2 + 512 * 1024 * 1024:
                raise InvalidMedia('На сервере мало свободного места. Освободи место и отправь /retry.')
            with tempfile.TemporaryDirectory(prefix='bot-audio-', dir=state.folder) as folder:
                path = Path(folder) / ('audio' + item['extension'])
                bot.download(item, path)
                media = inspect_audio(path, item, 'ar', Path(folder) / 'cover.jpg')
                result = api.import_audio(item, path, media, media['cover'])
        if not result.get('trackId'):
            raise APIError(502)
        state.mark(item, 'done', track=result['trackId'])
        duplicate = result.get('importStatus') in {'duplicate', 'existing'}
        bot.notify(config['ownerId'], item['messageId'],
                   ('Этот нашид уже есть в Muwa. Дубль не создан.' if duplicate else 'Нашид сохранён в черновики Muwa.') + '\nhttps://93.188.187.96/admin')
    except (APIError, BotError, InvalidMedia, OSError) as error:
        status = getattr(error, 'status', None)
        if isinstance(error, APIError) and status == 401:
            # One refresh; a wrong/revoked Muwa password stops the worker rather
            # than repeatedly locking the owner's account with failed logins.
            api.login(config['email'], config['password'])
            return True
        state.mark(item, 'error', error='HTTP_' + str(status) if status else type(error).__name__)
        if status in {401, 403}:
            raise
        bot.notify(config['ownerId'], item['messageId'],
                   str(error) if isinstance(error, InvalidMedia) else 'Не удалось загрузить нашид. Он сохранён в очереди ошибок. /retry — повторить; /status — состояние.')
    return True


def run(config, folder):
    logging.getLogger('httpx').setLevel(logging.WARNING)
    logging.getLogger('httpcore').setLevel(logging.WARNING)
    state = State(folder)
    bot, api = None, None
    try:
        bot = BotAPI(config['token'])
        api = MuwaAPI(config['backend'])
        me = bot.call('getMe')
        if not isinstance(me, dict) or me.get('id') != config['botId']:
            raise ValueError('Токен больше не соответствует настроенному боту.')
        # API and bot start independently on a reboot/deploy. Retry only a
        # temporary outage; invalid credentials/permissions still stop at once.
        for attempt in range(5):
            try:
                api.login(config['email'], config['password'])
                api.action({'action': 'lookup-telegram-import', 'source': {'botId': config['botId'], 'chatId': config['ownerId'], 'messageId': 1}})
                break
            except APIError as error:
                if (error.status >= 500 or error.status == 429) and attempt < 4:
                    time.sleep(60 if error.status == 429 else 2 ** (attempt + 1))
                    continue
                raise
        cursor = 'bot-updates:' + str(config['botId'])
        state.advance(cursor, config['nextOffset'] - 1)
        print('Muwa owner-only forwarding bot started; imported files remain drafts.', flush=True)
        while True:
            try:
                queued = bool(state.pending(f"bot:{config['botId']}:{config['ownerId']}", limit=1, provider='bot', include_errors=False))
                for update in bot.updates(state.cursor(cursor) + 1, timeout=1 if queued else 20):
                    identifier = update.get('update_id') if isinstance(update, dict) else None
                    if not update_id(identifier):
                        continue
                    enqueue(state, bot, config, update)
                    # Durable queue first, Telegram confirmation second. Crash
                    # recovery cannot acknowledge an audio message before save.
                    state.advance(cursor, identifier)
                if process_next(state, bot, api, config):
                    time.sleep(20)  # Existing backend upload quota remains intact.
            except BotError as error:
                if error.status in {401, 403, 409}:
                    raise
                print('bot_poll: HTTP_' + str(error.status), flush=True)
                time.sleep(error.retry_after)
    finally:
        if bot is not None: bot.close()
        if api is not None: api.close()
        state.close()
