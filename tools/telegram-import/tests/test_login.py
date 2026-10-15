import asyncio
import contextlib
import io
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from telethon.errors import SessionPasswordNeededError, PasswordHashInvalidError
from telethon import types
from telethon.tl.custom.qrlogin import QRLogin
from muwa_telegram_import.cli import arguments
from muwa_telegram_import.login import approve_login, show_approval, fresh_qr, UnexpectedQRResponse


class ApprovalTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.terminal = contextlib.ExitStack()
        for stream in ['stdin', 'stdout', 'stderr']:
            self.terminal.enter_context(patch('muwa_telegram_import.login.sys.' + stream + '.isatty', return_value=True))
        self.addCleanup(self.terminal.close)
        self.client = SimpleNamespace(get_me=AsyncMock(return_value=None), qr_login=AsyncMock(), sign_in=AsyncMock())
        self.reply = types.auth.LoginToken(datetime.now(timezone.utc), b'fixture-only-not-authentication')

    async def test_noninteractive_login_never_exports_a_token(self):
        with patch('muwa_telegram_import.login.sys.stdout.isatty', return_value=False):
            with self.assertRaises(ValueError):
                await approve_login(self.client)
        self.client.qr_login.assert_not_awaited()

    async def test_existing_session_does_not_generate_a_new_token(self):
        self.client.get_me.return_value = types.User(id=1)
        await approve_login(self.client)
        self.client.qr_login.assert_not_awaited()

    async def test_wait_handler_starts_before_owner_sees_qr(self):
        started = asyncio.Event()
        approved = asyncio.Event()
        async def wait(timeout=None):
            started.set()
            await approved.wait()
        qr = SimpleNamespace(wait=wait, _resp=self.reply)
        self.client.qr_login.return_value = qr
        def show(value):
            self.assertTrue(started.is_set())
            self.assertIs(value, qr)
            approved.set()
        with patch('muwa_telegram_import.login.show_approval', side_effect=show):
            await approve_login(self.client)

    async def test_expired_approval_refreshes_at_most_three_times(self):
        qr = SimpleNamespace(wait=AsyncMock(side_effect=asyncio.TimeoutError), _resp=self.reply)
        self.client.qr_login.return_value = qr
        output = io.StringIO()
        output.isatty = lambda: True
        with patch('muwa_telegram_import.login.show_approval'), contextlib.redirect_stdout(output):
            with self.assertRaises(ValueError):
                await approve_login(self.client)
        self.assertEqual(self.client.qr_login.await_count, 3)

    async def test_two_factor_password_is_hidden_and_sdk_details_not_printed(self):
        self.client.qr_login.return_value = SimpleNamespace(wait=AsyncMock(side_effect=SessionPasswordNeededError(None)), _resp=self.reply)
        self.client.sign_in.side_effect = [PasswordHashInvalidError(None), None]
        output = io.StringIO()
        output.isatty = lambda: True
        with patch('muwa_telegram_import.login.show_approval'), patch('muwa_telegram_import.login.getpass.getpass', return_value='fixture-private-password') as password, contextlib.redirect_stdout(output):
            await approve_login(self.client)
        self.assertEqual(password.call_count, 2)
        self.assertNotIn('fixture-private-password', output.getvalue())
        self.client.sign_in.assert_awaited_with(password='fixture-private-password')

    async def test_failed_display_removes_pending_wait_handler(self):
        stopped = asyncio.Event()
        async def wait(timeout=None):
            try:
                await asyncio.Event().wait()
            finally:
                stopped.set()
        self.client.qr_login.return_value = SimpleNamespace(wait=wait, _resp=self.reply)
        with patch('muwa_telegram_import.login.show_approval', side_effect=RuntimeError('display')):
            with self.assertRaises(RuntimeError):
                await approve_login(self.client)
        self.assertTrue(stopped.is_set())

    async def test_real_sdk_approved_reply_has_no_url_but_completes_verified_login(self):
        qr = QRLogin(SimpleNamespace(api_id=1, api_hash='fixture'), [])
        qr._resp = types.auth.LoginTokenSuccess(types.auth.Authorization(types.User(id=1)))
        with self.assertRaises(AttributeError):
            _ = qr.url
        self.client.qr_login.return_value = qr
        self.client.get_me.side_effect = [None, types.User(id=1)]
        with patch('muwa_telegram_import.login.show_approval') as show:
            await approve_login(self.client)
        show.assert_not_called()

    async def test_approved_reply_requires_fresh_server_identity(self):
        self.client.qr_login.return_value = SimpleNamespace(_resp=types.auth.LoginTokenSuccess(types.auth.Authorization(types.User(id=1))))
        with self.assertRaises(UnexpectedQRResponse):
            await fresh_qr(self.client)

    async def test_dc_migration_is_imported_before_a_qr_is_displayed(self):
        client = AsyncMock()
        client.qr_login.return_value = SimpleNamespace(_resp=types.auth.LoginTokenMigrateTo(2, b'fixture'))
        client.return_value = types.auth.LoginTokenSuccess(types.auth.Authorization(types.User(id=1)))
        client.get_me.return_value = types.User(id=1)
        self.assertIsNone(await fresh_qr(client))
        client._switch_dc.assert_awaited_once_with(2)
        self.assertEqual(client.call_args.args[0].token, b'fixture')

    async def test_password_required_during_initial_export_also_uses_hidden_prompt(self):
        self.client.qr_login.side_effect = SessionPasswordNeededError(None)
        with patch('muwa_telegram_import.login.getpass.getpass', return_value='fixture'):
            await approve_login(self.client)
        self.client.sign_in.assert_awaited_once_with(password='fixture')


class DisplayTests(unittest.TestCase):
    def test_qr_requires_second_screen_and_does_not_print_raw_token_link(self):
        output = io.StringIO()
        output.isatty = lambda: True
        with contextlib.redirect_stdout(output):
            show_approval(SimpleNamespace(url='tg://login?token=local-fixture'))
        self.assertNotIn('tg://login?token=local-fixture', output.getvalue())
        self.assertIn('втором экране', output.getvalue())
        self.assertIn('Не пересылай', output.getvalue())

    def test_qr_login_is_explicit_and_removed_link_mode_is_rejected(self):
        self.assertTrue(arguments(['telegram-login', '--qr']).qr)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            arguments(['telegram-login', '--qr', '--link'])
