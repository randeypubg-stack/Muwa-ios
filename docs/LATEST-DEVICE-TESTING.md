# Проверка Muwa на последних устройствах

Владелец 4 октября 2026 попросил включить последние iPhone/iPad и Android,
в частности iPhone 18 Pro Max с iOS 27. Проверяется тот же Muwa, с прежним
идентификатором `app.muwa.nasheeds` и API Beget.

## Матрица

- iPhone 18 Pro и iPhone 18 Pro Max: iOS 27.0.
- iPad Pro 13-inch (M5) и iPad mini (A17 Pro): iPadOS 27.0.
- Android: последний stable образ Google API 37.2, `google_apis_ps16k`,
  16-КБ страницы памяти. Телефоны 720×1280 и 1080×2400, планшет 1600×2560.
- Android API 35: дополнительная проверка совместимости на 1080×2400.

Apple использует официальный GitHub runner `xcode-27` и именно стабильный
`/Applications/Xcode_27.app/Contents/Developer`. Образ runner имеет статус
preview, но выбран Xcode 27.0, а не отдельно установленные Xcode 27.1/27.2 beta.
Отсутствие SDK или exact runtime 27.0 вызывает ошибку; старый iPhone/ОС не
переименовываются в запрошенную модель.

Android проверяет stable-индекс Google, затем выбирает реальный профиль из
установленного `avdmanager`. Последнее доступное поколение Pixel и планшетный
профиль фиксируются в манифесте. Переопределение экрана через `wm size`/density
записывается отдельно и не означает проверку на физическом Pixel этой модели.
`compileSdk`/`targetSdk` остаются 35: здесь проверка новых ОС, без скрытого
изменения поведения target SDK.

## Проверки и доказательства

В Apple capture сохраняются настоящий device type, UDID, runtime/build,
Xcode/SDK и исходное разрешение PNG. На Android сохраняются AVD, профиль,
system image, ОС/fingerprint, API/page size, physical/override geometry.

В матрицу входят Home, библиотека, очередь, плеер, профиль, Premium,
вертикальная/горизонтальная ориентация и увеличенный текст. iOS XCUITest
проверяет реальные перемещение строки очереди и создание/наполнение плейлиста
на iPhone 18 Pro Max. Холодный запуск проверяется независимо от ожидания сессии;
Android дополнительно проверяет запуск при нулевых системных анимациях.

Исходные PNG не перерисовываются и не меняют размер. Контрольный каталог в
review-сборках служит для воспроизводимых состояний UI; опубликованный каталог
и реальное прослушивание на сервере не подменяются этими fixtures.

Эмулятор не устанавливает реальную плавность 120 Гц, нагрев, расход батареи,
работу Bluetooth и покупки на физическом устройстве. Это требует установки
на соответствующее устройство. Запись Android launch-видео остаётся отдельной
опциональной проверкой.

## Источники

- Apple: https://www.apple.com/iphone/
- Runner/SDK: https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md
- Runner availability: https://github.com/actions/runner-images/issues/14404
- Google platforms: https://dl.google.com/android/repository/repository2-3.xml
- Google system images: https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml

Итоговые run IDs и результаты сохраняются в архиве проверки вместе с
манифестами и оригинальными скриншотами.
