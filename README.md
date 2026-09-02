# AI · четыре подхода

Flutter Web страница для одновременного сравнения четырёх способов работы с моделью: прямого ответа, ответа с кратким объяснением, ответа через улучшенный промт и ответов по пользовательским ролям. Node.js proxy хранит ключ только на сервере и обращается к OpenAI-compatible API.

## Структура

```text
.
├── lib/main.dart          # Тема и запуск Flutter-приложения
├── lib/pages/             # Страница сравнения
├── lib/comparison/        # Валидация, модели, API-клиент и параллельный координатор
├── web/index.html         # HTML bootstrap Flutter Web
├── backend/
│   ├── src/               # Express proxy, промты и клиент DeepSeek API
│   ├── .env.example       # Пример конфигурации
│   └── package.json
├── pubspec.yaml
└── README.md
```

## Требования

- Flutter SDK 3.3+ с включенной поддержкой web
- Node.js 18+ (рекомендуется Node.js 20+)
- API-ключ DeepSeek

## Запуск backend

```powershell
cd backend
npm install
Copy-Item .env.example .env
```

Заполните `DEEPSEEK_API_KEY` в `backend/.env`, затем запустите proxy:

```powershell
npm run dev
```

Сервер будет доступен на `http://localhost:3000`.

## Запуск Flutter Web

В отдельном терминале из корня проекта:

```powershell
flutter pub get
flutter run -d chrome
```

По умолчанию клиент обращается к `http://localhost:3000`. Чтобы задать другой базовый адрес proxy:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

Для запуска уже собранной production-версии локально:

```powershell
node scripts/serve-web.mjs
```

## Настройка модели

В `backend/.env` укажите ключ, модель и OpenAI-compatible endpoint:

```env
DEEPSEEK_MODEL=deepseek-v4-flash
DEEPSEEK_API_URL=https://api.deepseek.com/chat/completions
```

Для более мощной модели замените значение на `deepseek-v4-pro` и перезапустите backend.

## Безопасность

- `DEEPSEEK_API_KEY` читается только backend-процессом из `backend/.env`.
- `.env` исключен из Git и не попадает в Flutter Web bundle.
- CORS включается лишь при заданном `FRONTEND_ORIGIN`, что предназначено для локальной разработки.
- Proxy ограничивает размер JSON-запроса, количество сообщений и длину каждого сообщения.
- Клиент запускает четыре сценария параллельно и отменяет незавершённый пакет при повторном запуске.

## Проверки

```powershell
flutter analyze
flutter test
flutter build web
cd backend
npm test
```
