# Сравнение AI-моделей

Flutter Web-приложение отправляет один запрос одновременно в три модели:

- локальную GigaChat 3.1 через Ollama на `http://localhost:11434`;
- `deepseek-v4-flash` через DeepSeek API;
- `deepseek-v4-pro` через DeepSeek API.

Для каждого ответа интерфейс показывает время, число входных и выходных токенов и стоимость. Стоимость DeepSeek рассчитывается по фактическому `usage` ответа с учётом cache hit и действующих peak/off-peak тарифов. Локальный запуск GigaChat 3.1 отмечается как бесплатный.

## Запуск

Убедитесь, что Ollama доступна на порту `11434`. По умолчанию используется модель `hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M`; другое имя можно задать через `LOCAL_MODEL`.

```powershell
cd backend
npm install
Copy-Item .env.example .env
```

Укажите `DEEPSEEK_API_KEY` в `backend/.env`, затем запустите proxy:

```powershell
npm run dev
```

В отдельном терминале из корня проекта запустите Flutter Web:

```powershell
flutter pub get
flutter run -d chrome
```

Клиент по умолчанию обращается к `http://localhost:3000`. Другой адрес можно передать через `--dart-define=API_BASE_URL=...`.

## Конфигурация backend

```env
DEEPSEEK_API_KEY=your_deepseek_api_key_here
DEEPSEEK_API_URL=https://api.deepseek.com/chat/completions
OLLAMA_API_URL=http://localhost:11434/api/chat
LOCAL_MODEL=hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M
PORT=3000
FRONTEND_ORIGIN=http://localhost:8080
```

Ключ DeepSeek хранится только в backend и не попадает в Flutter Web bundle.

## Проверки

```powershell
flutter analyze
flutter test
flutter build web
cd backend
npm test
```
