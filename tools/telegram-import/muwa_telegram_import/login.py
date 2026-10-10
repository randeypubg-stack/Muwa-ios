"""Owner terminal login; short-lived Telegram approval tokens never enter logs."""
import asyncio
import getpass
import sys


class UnexpectedQRResponse(ValueError):
    pass


async def fresh_qr(client):
    from telethon import types, functions
    # Telethon 1.45 QRLogin assumes ExportLoginToken always returns LoginToken.
    # Telegram can also return an already-approved login or a DC migration.
    # This adapter is deliberately tied to the pinned SDK; validate the reply
    # before accessing its token/url/expiry, never serialize the reply itself.
    for _ in range(3):
        qr = await client.qr_login()
        reply = qr._resp
        if isinstance(reply, types.auth.LoginToken):
            return qr
        if isinstance(reply, types.auth.LoginTokenMigrateTo):
            print('Telegram: перенос подключения в нужный дата-центр.')
            await client._switch_dc(reply.dc_id)
            reply = await client(functions.auth.ImportLoginTokenRequest(reply.token))
        if isinstance(reply, types.auth.LoginTokenSuccess):
            if await client.get_me() is None:
                raise UnexpectedQRResponse('Telegram approval could not be verified.')
            print('Telegram: вход уже подтверждён, новый QR не нужен.')
            return None
    raise UnexpectedQRResponse('Telegram did not return a supported QR login response.')


def show_approval(qr):
    print('Telegram → Настройки → Устройства → Подключить устройство.')
    print('Открой Termius на втором экране и отсканируй QR телефоном с Telegram.')
    import qrcode
    image = qrcode.QRCode(border=4)
    image.add_data(qr.url)
    image.make(fit=True)
    image.print_ascii(out=sys.stdout, tty=True)
    print('Подтверди подключение своего сервера Muwa. Не пересылай QR.')
    sys.stdout.flush()


async def approve_login(client):
    # A systemd journal, pipe or remote tool transcript must never receive a
    # live token. The owner runs this only in their own interactive Termius.
    if not sys.stdin.isatty() or not sys.stdout.isatty() or not sys.stderr.isatty():
        raise ValueError('Вход по QR доступен только в твоём интерактивном Termius.')
    # Fetch the current server state, rather than trust the SDK's auth cache.
    if await client.get_me() is not None:
        return
    from telethon.errors import SessionPasswordNeededError, PasswordHashInvalidError
    for attempt in range(3):
        waiter = None
        try:
            qr = await fresh_qr(client)
            if qr is None:
                return
            waiter = asyncio.create_task(qr.wait(timeout=60))
            # Telethon must install the update handler before exposing the QR.
            await asyncio.sleep(0)
            show_approval(qr)
            await waiter
            return
        except asyncio.TimeoutError:
            print('QR-код истёк.' + (' Создаём новый.' if attempt < 2 else ' Повтори команду, когда будешь готов.'))
        except SessionPasswordNeededError:
            for password_attempt in range(3):
                password = getpass.getpass('Пароль двухэтапной проверки Telegram (скрыт): ')
                try:
                    await client.sign_in(password=password)
                    return
                except PasswordHashInvalidError:
                    print('Telegram отклонил пароль двухэтапной проверки.')
                finally:
                    password = None
            raise ValueError('Пароль Telegram не принят.') from None
        finally:
            if waiter is not None:
                if not waiter.done():
                    waiter.cancel()
                await asyncio.gather(waiter, return_exceptions=True)
    raise ValueError('Время подтверждения Telegram истекло.')
