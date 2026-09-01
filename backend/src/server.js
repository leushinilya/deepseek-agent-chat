import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import {pathToFileURL} from 'node:url';

const app = express();
const port = Number(process.env.PORT || 3000);
const model = process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash';
const maxMessages = 50;
const maxMessageLength = 8000;
const minResponseTokens = 50;
const maxResponseTokens = 4000;
const maxStopSequenceLength = 100;
const allowedRoles = new Set(['user', 'assistant']);
const systemPrompt = 'Ты полезный ИИ-агент. Отвечай ясно, дружелюбно и по делу.';
const defaultSettings = Object.freeze({
  responseFormat: 'freeform',
  maxTokens: 1000,
  stopSequence: null,
});

// CORS is enabled only when explicitly configured for local development.
if (process.env.FRONTEND_ORIGIN) {
  app.use(cors({origin: process.env.FRONTEND_ORIGIN, methods: ['POST']}));
}
app.use(express.json({limit: '100kb'}));

app.post('/api/chat', async (req, res) => {
  const validationError = validateMessages(req.body?.messages);
  if (validationError) return res.status(400).json({error: validationError});
  const settingsResult = parseSettings(req.body?.settings);
  if (settingsResult.error) return res.status(400).json({error: settingsResult.error});
  const settings = settingsResult.value;

  try {
    const deepSeekRequest = buildDeepSeekRequest(req.body.messages, settings);

    const response = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify(deepSeekRequest),
      signal: AbortSignal.timeout(60000),
    });

    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      console.error('DeepSeek request failed:', response.status, payload?.error?.message || 'Unknown error');
      return res.status(502).json({error: 'DeepSeek временно недоступен. Попробуйте еще раз.'});
    }

    const reply = payload?.choices?.[0]?.message?.content;
    if (typeof reply !== 'string' || !reply.trim()) {
      console.error('DeepSeek returned an invalid response shape.');
      return res.status(502).json({error: 'DeepSeek вернул некорректный ответ.'});
    }
    return res.json({reply});
  } catch (error) {
    console.error('DeepSeek connection error:', error instanceof Error ? error.message : 'Unknown error');
    return res.status(502).json({error: 'Не удалось получить ответ от DeepSeek. Проверьте подключение и повторите попытку.'});
  }
});

app.use((error, _req, res, _next) => {
  if (error instanceof SyntaxError) return res.status(400).json({error: 'Тело запроса должно быть корректным JSON.'});
  return res.status(500).json({error: 'Внутренняя ошибка сервера.'});
});

function validateMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return 'messages должен быть непустым массивом.';
  if (messages.length > maxMessages) return `Можно отправить не более ${maxMessages} сообщений за раз.`;
  for (const message of messages) {
    if (!message || typeof message !== 'object' || !allowedRoles.has(message.role)) return 'Каждое сообщение должно иметь роль user или assistant.';
    if (typeof message.content !== 'string' || !message.content.trim()) return 'Содержимое сообщения не должно быть пустым.';
    if (message.content.length > maxMessageLength) return `Одно сообщение не должно превышать ${maxMessageLength} символов.`;
  }
  return null;
}

function parseSettings(settings) {
  if (settings === undefined) return {value: {...defaultSettings}};
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
    return {error: 'settings должен быть объектом.'};
  }

  const responseFormat = settings.responseFormat ?? defaultSettings.responseFormat;
  if (responseFormat !== 'freeform' && responseFormat !== 'json') {
    return {error: 'settings.responseFormat должен быть freeform или json.'};
  }

  const maxTokens = settings.maxTokens ?? defaultSettings.maxTokens;
  if (!Number.isInteger(maxTokens) || maxTokens < minResponseTokens || maxTokens > maxResponseTokens) {
    return {error: `settings.maxTokens должен быть целым числом от ${minResponseTokens} до ${maxResponseTokens}.`};
  }

  const stopSequence = settings.stopSequence ?? null;
  if (stopSequence !== null && typeof stopSequence !== 'string') {
    return {error: 'settings.stopSequence должен быть строкой или null.'};
  }
  if (typeof stopSequence === 'string' && stopSequence.length > maxStopSequenceLength) {
    return {error: `settings.stopSequence не должен превышать ${maxStopSequenceLength} символов.`};
  }

  return {
    value: {
      responseFormat,
      maxTokens,
      stopSequence: typeof stopSequence === 'string' && stopSequence.trim() ? stopSequence : null,
    },
  };
}

function buildSystemPrompt(settings) {
  if (settings.responseFormat === 'json') {
    return `${systemPrompt} Верни ответ только как корректный JSON без Markdown-обрамления и пояснений вне JSON.`;
  }
  return systemPrompt;
}

function buildDeepSeekRequest(messages, settings) {
  const request = {
    model,
    messages: [
      {role: 'system', content: buildSystemPrompt(settings)},
      ...messages,
    ],
    temperature: 0.7,
    max_tokens: settings.maxTokens,
  };
  if (settings.stopSequence) request.stop = settings.stopSequence;
  return request;
}

const isMainModule = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMainModule) {
  if (!process.env.DEEPSEEK_API_KEY) {
    console.error('DEEPSEEK_API_KEY is not configured. Add it to backend/.env.');
    process.exit(1);
  }
  app.listen(port, () => console.log(`DeepSeek proxy is listening on http://localhost:${port}`));
}

export {
  app,
  buildDeepSeekRequest,
  buildSystemPrompt,
  defaultSettings,
  parseSettings,
  validateMessages,
};
