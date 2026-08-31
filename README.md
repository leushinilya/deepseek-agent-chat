# DeepSeek Agent Chat

Минималистичный Flutter Web чат с ИИ-агентом. Flutter-клиент хранит историю только в памяти текущей сессии, а Node.js proxy хранит ключ DeepSeek на сервере и отправляет запросы через OpenAI-compatible API.

## Структура

```text
.
├── lib/main.dart          # Flutter Web интерфейс и состояние чата
├── web/index.html         # HTML bootstrap Flutter Web
├── backend/
│   ├── src/server.js      # Express proxy, валидация и DeepSeek API
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

По умолчанию клиент обращается к `http://localhost:3000/api/chat`. Чтобы задать другой адрес proxy:

```powershell
flutter run -d chrome --dart-define=API_URL=http://localhost:3000/api/chat
```

Для запуска уже собранной production-версии локально:

```powershell
node scripts/serve-web.mjs
```

## Настройка модели

В `backend/.env` используйте:

```env
DEEPSEEK_MODEL=deepseek-v4-flash
```

Для более мощной модели замените значение на `deepseek-v4-pro` и перезапустите backend.

## Безопасность

- `DEEPSEEK_API_KEY` читается только backend-процессом из `backend/.env`.
- `.env` исключен из Git и не попадает в Flutter Web bundle.
- CORS включается лишь при заданном `FRONTEND_ORIGIN`, что предназначено для локальной разработки.
- Proxy ограничивает размер JSON-запроса, количество сообщений и длину каждого сообщения.
