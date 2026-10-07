import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
import httpx
from muwa_telegram_import.api import MuwaAPI
from muwa_telegram_import.bot import BotAPI, BotError, MAX_BOT_AUDIO, audio_item, enqueue, owner_message, pair_owner, process_next
from muwa_telegram_import.media import InvalidMedia
from muwa_telegram_import.state import State

TOKEN = '123456:' + 'a' * 32  # Deliberately fabricated, not a live bot token.
OWNER = 123456789
BOT = 987654321
CONFIG = {'ownerId': OWNER, 'botId': BOT, 'email': 'owner@example.invalid', 'password': 'fixture'}


def message(sender=OWNER, chat=OWNER, chat_type='private', identifier=5):
    return {'update_id': 10, 'message': {'message_id': identifier, 'from': {'id': sender, 'is_bot': False},
            'chat': {'id': chat, 'type': chat_type}, 'audio': {'file_id': 'fixture-file', 'file_size': 32,
            'file_name': 'نشيد.mp3', 'title': 'عنوان', 'performer': 'فنان'}}}


class OwnerBotTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.state = State(Path(self.folder.name))
        self.addCleanup(self.state.close)
        self.bot = Mock()

    def test_actual_sender_and_private_chat_are_required_not_forwarded_identity(self):
        forged = message(sender=333)
        forged['message']['forward_origin'] = {'type': 'user', 'sender_user': {'id': OWNER}}
        for update in [forged, message(chat=-1000000000010, chat_type='supergroup'), message(chat=222), {}, {'message': []}]:
            self.assertIsNone(owner_message(update, OWNER))
            enqueue(self.state, self.bot, CONFIG, update)
        self.assertEqual(self.state.counts(), {})
        self.bot.notify.assert_not_called()
        self.assertIsNotNone(owner_message(message(), OWNER))

    def test_duplicate_delivery_is_durable_and_completed_message_is_not_requeued(self):
        enqueue(self.state, self.bot, CONFIG, message())
        self.state.advance('updates', 10)
        item = self.state.pending(provider='bot')[0]
        self.assertEqual(item['title'], 'عنوان')
        self.state.mark(item, 'done', track='fixture-track')
        enqueue(self.state, self.bot, CONFIG, message())
        self.assertEqual(self.state.counts(), {'done': 1})
        with self.state.db:
            self.assertEqual(self.state.db.execute('SELECT track FROM items').fetchone()[0], 'fixture-track')
        # Cursor is committed separately only after the work item exists.
        self.assertEqual(self.state.cursor('updates'), 10)

    def test_documents_supported_but_voice_video_and_oversized_files_rejected(self):
        msg = message()['message']
        self.assertEqual(audio_item(msg, BOT, OWNER)['extension'], '.mp3')
        document = dict(msg, document=msg['audio']); document.pop('audio')
        self.assertEqual(audio_item(document, BOT, OWNER)['kind'], 'bot')
        for bad in [dict(msg, audio={'file_id': 'f', 'file_size': MAX_BOT_AUDIO + 1, 'file_name': 'x.mp3'}),
                    dict(msg, audio={'file_id': 'f', 'file_size': 3, 'file_name': 'x.ogg'}),
                    {'message_id': 5, 'voice': {'file_id': 'f'}}, {'message_id': 5, 'video': {'file_id': 'f'}}]:
            with self.assertRaises(InvalidMedia): audio_item(bad, BOT, OWNER)

    def test_failed_file_is_not_automatically_retried_forever(self):
        enqueue(self.state, self.bot, CONFIG, message())
        item = self.state.pending(provider='bot')[0]
        self.state.mark(item, 'error', error='InvalidMedia')
        self.assertEqual(self.state.pending(provider='bot', include_errors=False), [])
        self.assertEqual(len(self.state.pending(provider='bot')), 1)  # Preserve legacy behaviour.
        self.assertEqual(self.state.retry_errors('bot'), 1)
        self.assertEqual(len(self.state.pending(provider='bot', include_errors=False)), 1)

    def test_pairing_requires_unpredictable_nonce_in_owner_private_chat(self):
        nonce = 'fixture-pairing-nonce'
        wrong = message(sender=333, chat=333)
        wrong['message']['text'] = '/start wrong'
        group = message(chat=-1000000012345, chat_type='channel')
        group['message']['text'] = '/start ' + nonce
        valid = message();valid['update_id'] = 12;valid['message']['text'] = '/start ' + nonce
        self.bot.updates.return_value = [wrong, group, valid]
        with patch('muwa_telegram_import.bot.secrets.token_urlsafe', return_value=nonce), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pair_owner(self.bot, 'FixtureMuwaBot'), (OWNER, 13))

    def test_success_and_existing_source_do_not_redownload_or_overwrite_metadata(self):
        enqueue(self.state, self.bot, CONFIG, message())
        api = Mock();api.action.return_value = {'ok': True, 'trackId': 'existing', 'importStatus': 'existing'}
        self.assertTrue(process_next(self.state, self.bot, api, CONFIG))
        self.bot.download.assert_not_called()
        api.import_audio.assert_not_called()
        self.assertEqual(self.state.counts(), {'done': 1})
        self.assertIn('Дубль не создан', self.bot.notify.call_args.args[2])

    def test_invalid_audio_is_removed_and_retained_as_retryable_error(self):
        enqueue(self.state, self.bot, CONFIG, message())
        api = Mock();api.action.return_value = {'ok': True, 'importStatus': 'missing'}
        self.bot.download.side_effect = lambda item, path: path.write_bytes(b'not-real-audio')
        with patch('muwa_telegram_import.bot.shutil.disk_usage', return_value=Mock(free=2**30)):
            self.assertTrue(process_next(self.state, self.bot, api, CONFIG))
        self.assertEqual(self.state.counts(), {'error': 1})
        self.assertEqual(list(Path(self.folder.name).glob('bot-audio-*')), [])
        api.import_audio.assert_not_called()


class BotTransportTests(unittest.TestCase):
    def test_token_and_response_body_are_not_in_http_errors(self):
        bot = BotAPI(TOKEN, transport=httpx.MockTransport(lambda request: httpx.Response(401, json={'ok': False, 'error_code': 401, 'description': 'private-response'})))
        self.addCleanup(bot.close)
        with self.assertRaises(BotError) as caught: bot.call('getMe')
        self.assertEqual(caught.exception.status, 401)
        self.assertNotIn(TOKEN, str(caught.exception))
        self.assertNotIn('private-response', str(caught.exception))

    def test_file_path_cannot_escape_telegram_host_and_redirects_are_rejected(self):
        for path in ['../private', 'https://other.invalid/audio', '/file.mp3', 'audio//file.mp3', 'audio/file.mp3?token=x']:
            requests = []
            def handle(request):
                requests.append(request)
                return httpx.Response(200, json={'ok': True, 'result': {'file_path': path, 'file_size': 32}})
            bot = BotAPI(TOKEN, transport=httpx.MockTransport(handle))
            with tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(BotError): bot.download({'fileId': 'fixture', 'sizeBytes': 32}, Path(folder)/'audio.mp3')
            bot.close()
            self.assertEqual(len(requests), 1)
        def redirect(request):
            if request.url.path.endswith('getFile'):return httpx.Response(200,json={'ok':True,'result':{'file_path':'audio/file.mp3','file_size':32}})
            return httpx.Response(302,headers={'Location':'https://other.invalid/file'})
        bot=BotAPI(TOKEN,transport=httpx.MockTransport(redirect));self.addCleanup(bot.close)
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(BotError):bot.download({'fileId':'fixture','sizeBytes':32},Path(folder)/'audio.mp3')

    def test_partial_or_excessive_download_is_removed(self):
        for actual in [b'short', b'x'*33]:
            def handle(request):
                if request.url.path.endswith('getFile'):return httpx.Response(200,json={'ok':True,'result':{'file_path':'audio/file.mp3','file_size':32}})
                return httpx.Response(200,content=actual)
            bot=BotAPI(TOKEN,transport=httpx.MockTransport(handle))
            with tempfile.TemporaryDirectory() as folder:
                target=Path(folder)/'audio.mp3'
                with self.assertRaises(InvalidMedia):bot.download({'fileId':'fixture','sizeBytes':32},target)
                self.assertFalse(target.exists())
            bot.close()

    def test_existing_upload_client_uses_real_bot_namespace_and_cannot_publish(self):
        seen=[]
        def handle(request):
            body=json.loads(request.content);seen.append(body)
            return httpx.Response(200,json={'ok':True,'trackId':'already-saved','importStatus':'existing'})
        api=MuwaAPI('https://muwa.invalid',transport=httpx.MockTransport(handle));self.addCleanup(api.close)
        item=audio_item(message()['message'],BOT,OWNER)
        result=api.import_audio(item,Path('not-opened'),{'audioSha256':'a'*64})
        self.assertEqual(result['trackId'],'already-saved')
        self.assertEqual(seen,[{'action':'lookup-telegram-import','source':{'botId':BOT,'chatId':OWNER,'messageId':5,'audioSha256':'a'*64}}])
