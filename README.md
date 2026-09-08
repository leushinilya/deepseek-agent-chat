# ИИ-агенты и сравнение моделей

Flutter-приложение объединяет исходный экран сравнения моделей с системой настраиваемых ИИ-агентов и отдельных чатов. Агенты, чаты и сообщения сохраняются локально через `shared_preferences`; запросы к моделям идут через Express backend, поэтому секрет DeepSeek не попадает в клиентский bundle.

Поддерживаемые модели:

- `GigaChat 3.1 (локальная)` — официальный Ollama Chat API;
- `deepseek-v4-flash` — DeepSeek API;
- `deepseek-v4-pro` — DeepSeek API.

## Конфигурация

Создайте `backend/.env` на основе `backend/.env.example`:

```env
DEEPSEEK_API_KEY=your_deepseek_api_key_here
DEEPSEEK_API_URL=https://api.deepseek.com/chat/completions
OLLAMA_BASE_URL=http://localhost:11434
LOCAL_MODEL=hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M
PORT=3000
FRONTEND_ORIGIN=http://localhost:8080
```

`DEEPSEEK_API_KEY` нужен только для DeepSeek. Если он не задан, backend продолжит работать с Ollama, а в DeepSeek-чате появится понятная ошибка конфигурации. Никогда не передавайте этот ключ через `--dart-define` и не добавляйте `.env` в Git.

Полный Ollama endpoint можно переопределить совместимой переменной `OLLAMA_API_URL`; обычно достаточно `OLLAMA_BASE_URL`. Адрес Flutter-клиента к backend задаётся через `--dart-define=API_BASE_URL=...`, по умолчанию `http://localhost:3000`.

## Ollama и локальная модель

1. Установите и запустите [Ollama](https://ollama.com/).
2. Загрузите модель, указанную в `LOCAL_MODEL`:

```powershell
ollama pull hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M
```

3. Если Ollama не запустилась автоматически:

```powershell
ollama serve
```

4. Проверьте установку:

```powershell
ollama list
```

Для другого тега/квантизации измените только `LOCAL_MODEL` в backend-конфигурации. Внутренний клиентский идентификатор `local-gigachat` при этом остаётся стабильным.

## Запуск

```powershell
cd backend
npm install
npm run dev
```

В отдельном терминале из корня проекта:

```powershell
flutter pub get
flutter run -d chrome
```

Для production-развёртывания ограничьте `FRONTEND_ORIGIN` реальным origin приложения и храните `DEEPSEEK_API_KEY` в защищённой конфигурации сервера.

## Проверки

```powershell
flutter analyze
flutter test
flutter build web
cd backend
npm test
```

Тесты используют подменяемые хранилища и LLM-провайдеры, поэтому реальные API для них не требуются.
