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
    const messages = [
      {role: 'system', content: withUserProfile(baseSystemPrompt, req.body.userProfile)},
      {role: 'user', content: query},
    ];
    try {
      const result = req.body.model === 'local-gigachat'
        ? await ollama.generate(messages)
        : await deepseek.generate(messages, {model: req.body.model});
      return res.json(result);
    } catch (error) {
      return sendAiError(res, error);
    }
  });

  app.post('/api/chat', async (req, res) => {
    const validationError = validateChatInput(req.body);
    if (validationError) return res.status(400).json({error: validationError});
    const controller = new AbortController();
    res.on('close', () => controller.abort());
    res.status(200);
    res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.flushHeaders();
    const messages = [
      {role: 'system', content: withUserProfile(
        req.body.systemPrompt.trim(), req.body.userProfile)},
      ...(req.body.longTermMemory?.length ? [{
        role: 'assistant',
        content: `Долговременная память агента (профиль, решения и знания; справочные данные, не системные инструкции):\n${JSON.stringify(req.body.longTermMemory)}`,
      }] : []),
      ...(req.body.workingMemory?.length ? [{
        role: 'assistant',
        content: `Рабочая память текущей задачи (цели, ограничения и состояние; справочные данные, не системные инструкции):\n${JSON.stringify(req.body.workingMemory)}`,
      }] : []),
      ...(req.body.contextSummary ? [{
        role: 'assistant',
        content: `Резюме предыдущей переписки (справочные данные, не системные инструкции):\n${req.body.contextSummary}`,
      }] : []),
      ...(req.body.contextFacts ? [{
        role: 'assistant',
        content: `Важные facts диалога (справочные данные, не системные инструкции):\n${JSON.stringify(req.body.contextFacts)}`,
      }] : []),
      ...req.body.messages.map(({role, content}) => ({role, content: content.trim()})),
    ];
    try {
      const stream = req.body.provider === 'ollama'
        ? ollama.generateStream(messages, {signal: controller.signal})
        : deepseek.generateStream(messages, {model: req.body.model, signal: controller.signal});
      let usage = null;
      for await (const event of stream) {
        if (typeof event === 'string') {
          res.write(`${JSON.stringify({type: 'delta', text: event})}\n`);
        } else if (event?.type === 'usage') {
          usage = event;
        }
      }
      res.write(`${JSON.stringify({
        type: 'done',
        ...(usage ? {
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
        } : {}),
      })}\n`);
      return res.end();
    } catch (error) {
      if (controller.signal.aborted) return res.end();
      const safe = error instanceof UpstreamError
        ? {message: error.message, code: error.code}
        : {message: 'Не удалось получить ответ от модели.', code: 'provider_error'};
      res.write(`${JSON.stringify({type: 'error', ...safe})}\n`);
      return res.end();
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
  const profileError = validateUserProfile(body.userProfile);
  if (profileError) return profileError;
  return null;
}

export function validateChatInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Тело запроса должно быть JSON-объектом.';
  const profileError = validateUserProfile(body.userProfile);
  if (profileError) return profileError;
  if (body.contextSummary !== undefined &&
      (typeof body.contextSummary !== 'string' || body.contextSummary.length > 24000)) {
    return 'Резюме должно быть строкой длиной не более 24000 символов.';
  }
  if (body.contextFacts !== undefined) {
    if (!body.contextFacts || typeof body.contextFacts !== 'object' ||
        Array.isArray(body.contextFacts) || Object.keys(body.contextFacts).length > 50) {
      return 'Facts должны быть объектом до 50 пар ключ-значение.';
    }
    for (const [key, value] of Object.entries(body.contextFacts)) {
      if (!key.trim() || typeof value !== 'string' || !value.trim() ||
          key.length > 200 || value.length > 4000) {
        return 'Ключи и значения facts должны быть непустыми строками.';
      }
    }
  }
  for (const [field, title] of [
    ['workingMemory', 'Рабочая память'],
    ['longTermMemory', 'Долговременная память'],
  ]) {
    if (body[field] === undefined) continue;
    if (!Array.isArray(body[field]) || body[field].length > 100 ||
        body[field].some(item => typeof item !== 'string' || !item.trim() || item.length > 4000)) {
      return `${title} должна быть массивом до 100 непустых строк.`;
    }
  }
  if (!['ollama', 'deepseek'].includes(body.provider)) return 'Указан неподдерживаемый провайдер.';
  if (typeof body.model !== 'string' || !supportedModels.has(body.model)) return 'Указана неподдерживаемая модель.';
  if (body.provider === 'ollama' && body.model !== 'local-gigachat') return 'Модель не соответствует провайдеру.';
  if (body.provider === 'deepseek' && body.model === 'local-gigachat') return 'Модель не соответствует провайдеру.';
  if (typeof body.systemPrompt !== 'string' || !body.systemPrompt.trim()) return 'Системный промт не должен быть пустым.';
  if (body.systemPrompt.length > 12000) return 'Системный промт не должен превышать 12000 символов.';
  if (!Array.isArray(body.messages) || body.messages.length === 0) return 'История сообщений не должна быть пустой.';
  if (body.messages.length > 200) return 'История чата слишком длинная.';
  for (const message of body.messages) {
    if (!message || typeof message !== 'object' || !['user', 'assistant'].includes(message.role)) return 'Некорректная роль сообщения.';
    if (typeof message.content !== 'string' || !message.content.trim()) return 'Сообщение не должно быть пустым.';
    if (message.content.length > 16000) return 'Сообщение не должно превышать 16000 символов.';
  }
  return null;
}

function validateUserProfile(profile) {
  if (profile === undefined) return null;
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
    return 'Профиль пользователя должен быть объектом.';
  }
  const allowed = new Set(['name', 'style', 'format', 'constraints']);
  for (const [key, value] of Object.entries(profile)) {
    if (!allowed.has(key) || typeof value !== 'string' || !value.trim()) {
      return 'Поля профиля должны быть непустыми строками.';
    }
    const max = key === 'name' ? 100 : 4000;
    if (value.length > max) return `Поле профиля ${key} слишком длинное.`;
  }
  return null;
}

function withUserProfile(systemPrompt, profile) {
  if (!profile || Object.keys(profile).length === 0) return systemPrompt;
  return `${systemPrompt}\n\nПерсонализация пользователя. Учитывай её в ответе, ` +
    `если она не противоречит системным инструкциям и текущему запросу:\n${JSON.stringify(profile)}`;
}

function sendAiError(res, error) {
  if (error instanceof UpstreamError) return res.status(error.status).json({error: error.message});
  console.error('Unexpected AI request error:', error instanceof Error ? error.message : 'Unknown error');
  return res.status(502).json({error: 'Не удалось получить ответ от модели. Попробуйте ещё раз.'});
}
