import cors from 'cors';
import express from 'express';

import {parseJsonObject, requiredString, UpstreamError} from './deepseek.js';
import {baseSystemPrompt, explainedMessages, promptImprovementMessages, roleMessages} from './prompts.js';

export const limits = Object.freeze({maxMessages: 50, maxMessageLength: 8000, maxQueryLength: 8000, maxRoles: 10, maxRoleLength: 80});
const allowedChatRoles = new Set(['user', 'assistant']);
const scenarios = new Set(['direct', 'explained', 'prompted', 'roles']);

export function createApp({ai, frontendOrigin}) {
  const app = express();
  if (frontendOrigin) app.use(cors({origin: frontendOrigin, methods: ['POST']}));
  app.use(express.json({limit: '100kb'}));

  app.post('/api/chat', async (req, res) => {
    const validationError = validateMessages(req.body?.messages);
    if (validationError) return res.status(400).json({error: validationError});
    try {
      const reply = await ai.complete([{role: 'system', content: baseSystemPrompt}, ...req.body.messages]);
      return res.json({reply});
    } catch (error) {
      return sendAiError(res, error);
    }
  });

  app.post('/api/compare/:scenario', async (req, res) => {
    const {scenario} = req.params;
    if (!scenarios.has(scenario)) return res.status(404).json({error: 'Неизвестный сценарий сравнения.'});
    const validationError = validateComparisonInput(req.body, scenario);
    if (validationError) return res.status(400).json({error: validationError});
    const query = req.body.query.trim();
    const roles = scenario === 'roles' ? normalizeRoles(req.body.roles) : [];
    try {
      if (scenario === 'direct') {
        const answer = await ai.complete([{role: 'system', content: baseSystemPrompt}, {role: 'user', content: query}]);
        return res.json({answer});
      }
      if (scenario === 'explained') {
        const data = parseJsonObject(await ai.complete(explainedMessages(query), {json: true}));
        return res.json({answer: requiredString(data, 'answer'), reasoningSummary: requiredString(data, 'reasoningSummary')});
      }
      if (scenario === 'prompted') {
        const promptData = parseJsonObject(await ai.complete(promptImprovementMessages(query), {json: true}));
        const generatedPrompt = requiredString(promptData, 'generatedPrompt');
        const answer = await ai.complete([{role: 'system', content: baseSystemPrompt}, {role: 'user', content: generatedPrompt}]);
        return res.json({generatedPrompt, answer});
      }
      const data = parseJsonObject(await ai.complete(roleMessages(query, roles), {json: true}));
      return res.json({answers: normalizeRoleAnswers(data.answers, roles)});
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

export function normalizeRoles(roles) {
  if (!Array.isArray(roles)) return [];
  return roles.filter((role) => typeof role === 'string').map((role) => role.trim()).filter(Boolean);
}

export function validateComparisonInput(body, scenario) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Тело запроса должно быть JSON-объектом.';
  if (typeof body.query !== 'string' || !body.query.trim()) return 'Запрос не должен быть пустым.';
  if (body.query.length > limits.maxQueryLength) return `Запрос не должен превышать ${limits.maxQueryLength} символов.`;
  if (scenario !== 'roles') return null;
  if (!Array.isArray(body.roles)) return 'roles должен быть массивом.';
  const roles = normalizeRoles(body.roles);
  if (roles.length === 0) return 'Укажите хотя бы одну непустую роль.';
  if (roles.length > limits.maxRoles) return `Можно указать не более ${limits.maxRoles} ролей.`;
  if (roles.some((role) => role.length > limits.maxRoleLength)) return `Название роли не должно превышать ${limits.maxRoleLength} символов.`;
  if (roles.length !== body.roles.length) return 'Список ролей содержит пустые или некорректные элементы.';
  return null;
}

export function validateMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return 'messages должен быть непустым массивом.';
  if (messages.length > limits.maxMessages) return `Можно отправить не более ${limits.maxMessages} сообщений за раз.`;
  for (const message of messages) {
    if (!message || typeof message !== 'object' || !allowedChatRoles.has(message.role)) return 'Каждое сообщение должно иметь роль user или assistant.';
    if (typeof message.content !== 'string' || !message.content.trim()) return 'Содержимое сообщения не должно быть пустым.';
    if (message.content.length > limits.maxMessageLength) return `Одно сообщение не должно превышать ${limits.maxMessageLength} символов.`;
  }
  return null;
}

function normalizeRoleAnswers(rawAnswers, requestedRoles) {
  if (!Array.isArray(rawAnswers)) throw new UpstreamError('Модель вернула некорректный список ответов по ролям.');
  const byRole = new Map();
  for (const item of rawAnswers) {
    if (!item || typeof item !== 'object') continue;
    const role = typeof item.role === 'string' ? item.role.trim() : '';
    const answer = typeof item.answer === 'string' ? item.answer.trim() : '';
    if (role && answer && !byRole.has(role.toLocaleLowerCase('ru'))) byRole.set(role.toLocaleLowerCase('ru'), answer);
  }
  const normalized = requestedRoles.map((role) => ({role, answer: byRole.get(role.toLocaleLowerCase('ru'))})).filter((item) => typeof item.answer === 'string' && item.answer.length > 0);
  if (normalized.length === 0) throw new UpstreamError('Модель не сформировала ни одного корректного ответа по ролям.');
  return normalized;
}

function sendAiError(res, error) {
  if (error instanceof UpstreamError) return res.status(error.status).json({error: error.message});
  console.error('Unexpected AI request error:', error instanceof Error ? error.message : 'Unknown error');
  return res.status(502).json({error: 'Не удалось получить ответ от модели. Попробуйте ещё раз.'});
}
