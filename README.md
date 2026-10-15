# Muwa

Нативное приложение нашидов: iOS/iPadOS — SwiftUI и AVPlayer, Android — Kotlin,
Jetpack Compose и Media3. Backend и панель владельца работают на Beget.
Имя **Muwa**, идентификатор **app.muwa.nasheeds**, версия **1.4.0**, iOS build **54**, Android build **55**.
Сопоставление платформ: [Android / iOS](docs/ANDROID_IOS_PARITY_BUILD55.md).

Актуальное состояние и ограничения: [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).
Карта проекта: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Перенос в новый чат Codex: [docs/PORTABLE_PROJECT.md](docs/PORTABLE_PROJECT.md).

## Где работать

| Папка | Содержание |
| --- | --- |
| `native-patches/Sources` | Актуальные Swift-экраны, модели, сервисы и система оформления |
| `native-patches/Resources`, `Configuration` | Ресурсы iOS и настройки CarPlay |
| `source-base` | Проверенная неизменяемая основа Xcode-проекта |
| `android` | Полный Gradle-проект Android |
| `backend` | API, существующие сервисы, схемы и миграции PostgreSQL |
| `admin-panel` | Панель: каталог, субтитры, модерация, общие элементы и стили |
| `branding` | Исходные логотипы и их контрольные суммы |
| `tools` | Развёртывание, Telegram-импорт и локальное распознавание |
| `scripts`, `tests`, `.github/workflows` | Сборка, переносимый архив, проверки и CI |
| `docs` | Архитектура, актуальные решения и датированные отчёты |

## Собрать проект

Python 3.10+ собирает полный Xcode-проект из отслеживаемой основы и актуальных
исходников; загрузка кода из Floot или другого CDN не требуется:

```sh
python3 scripts/assemble_ios.py --output build-src/MuwaNasheedsNative
python3 tests/check_native_registration.py build-src/MuwaNasheedsNative
```

Откройте `build-src/MuwaNasheedsNative/MuwaNasheeds.xcodeproj` на macOS в Xcode,
схема `MuwaNasheeds`. Канонические изменения вносите в `native-patches`, затем
генерируйте проект в новую/пустую папку. Собранная папка не является второй
реализацией приложения. iOS deployment target — 17.0; актуальные CI-проверки
используют стабильный Xcode 27.0. Установка на iPhone требует подписи Apple;
CI IPA не подписан. [CarPlay](docs/CarPlay.md) требует соответствующего provisioning.

Android: откройте `android` в Android Studio (JDK 17, SDK 35); Gradle wrapper
фиксирует 8.10.2. Локальные пути SDK укажите отдельно, не в исходном архиве.

```sh
cd android
./gradlew assembleDebug testDebugUnitTest lintDebug
```

Для backend и панели отдельно выполните `npm ci`, затем `npm run build`.
Настройка backend, переменные окружения и миграции описаны в
[backend/README.md](backend/README.md). Панель — [admin-panel/README.md](admin-panel/README.md).

## Важные решения

Опубликованные нашиды видны гостям до входа. Вход нужен для личных данных и
действий владельца. Каталог и медиа хранятся на сервере; их содержимое не
вшито в исходники. Floot больше не нужен этой бете, старый проект не изменяется.

Premium-ограничения отключены для функционального тестирования. Локальный
Whisper large-v3 распознаёт загрузки на сервере; **каждый результат остаётся
приватным черновиком до явного сохранения владельцем**. Загрузка, публикация
аудио и воспроизведение не ждут распознавания. Платные AI-провайдеры выключены;
точность арабских диалектов нужно проверять по записям и эталонному тексту.

Шрифты, цвета, анимации и фон отделены от экранов. Утверждённое расположение
нижнего бара закреплено правилами `AGENTS.md` и проверками геометрии. Перестройка
папок от 14 октября не меняет дизайн. Новые предложенные фоновые концепции
ещё не выбраны владельцем.

Владелец разрешил публичный GitHub. Секреты, Telegram-сессии, ключи подписи,
кэши и рабочая база в исходный архив не входят. Датированные отчёты в `docs`
описывают свои версии; при расхождении сверяйтесь с `CURRENT_STATE.md`.
