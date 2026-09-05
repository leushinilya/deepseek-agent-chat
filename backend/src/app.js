import cors from 'cors';
import express from 'express';

import {UpstreamError} from './deepseek.js';
import {baseSystemPrompt} from './prompts.js';

export const limits = Object.freeze({maxQueryLength: 8000});
const supportedModels = new Set(['local-gigachat', 'deepseek-v4-flash', 'deepseek-v4-pro']);

export function createApp({deepseek, ollama, frontendOrigin}) {
  const app = express();
  if (frontendOrigin) app.use(cors({origin: frontendOrigin, methods: ['POST']}));
  app.use(express.json({limit: '100kb'}));

  app.post('/api/compare', async (req, res) => {
    const validationError = validateComparisonInput(req.body);
    if (validationError) return res.status(400).json({error: validationError});
    const query = req.body.query.trim();
    const messages = [{role: 'system', content: baseSystemPrompt}, {role: 'user', content: query}];
    try {
      const result = req.body.model === 'local-gigachat'
        ? await ollama.generate(messages)
        : await deepseek.generate(messages, {model: req.body.model});
      return res.json(result);
    } catch (error) {
      return sendAiError(res, error);
    }
  });

  app.use((error, _req, res, _next) => {
    if (error instanceof SyntaxError) return res.status(400).json({error: 'Тело запроса должно быть корректным JSON.'});
    return res.status(500).json({error: 'Внутренняя ошибка сервера.'});
  });
  return app;
}

export function validateComparisonInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Тело запроса должно быть JSON-объектом.';
  if (typeof body.query !== 'string' || !body.query.trim()) return 'Запрос не должен быть пустым.';
  if (body.query.length > limits.maxQueryLength) return `Запрос не должен превышать ${limits.maxQueryLength} символов.`;
  if (typeof body.model !== 'string' || !supportedModels.has(body.model)) return 'Указана неподдерживаемая модель.';
  return null;
}

function sendAiError(res, error) {
  if (error instanceof UpstreamError) return res.status(error.status).json({error: error.message});
  console.error('Unexpected AI request error:', error instanceof Error ? error.message : 'Unknown error');
  return res.status(502).json({error: 'Не удалось получить ответ от модели. Попробуйте ещё раз.'});
}
