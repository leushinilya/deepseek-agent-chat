import 'dotenv/config';
import cors from 'cors';
import express from 'express';

const app = express();
const port = Number(process.env.PORT || 3000);
const model = process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash';
const maxMessages = 50;
const maxMessageLength = 8000;
const allowedRoles = new Set(['user', 'assistant']);
const systemPrompt = 'Ты полезный ИИ-агент. Отвечай ясно, дружелюбно и по делу.';

if (!process.env.DEEPSEEK_API_KEY) {
  console.error('DEEPSEEK_API_KEY is not configured. Add it to backend/.env.');
  process.exit(1);
}

// CORS is enabled only when explicitly configured for local development.
if (process.env.FRONTEND_ORIGIN) {
  app.use(cors({origin: process.env.FRONTEND_ORIGIN, methods: ['POST']}));
}
app.use(express.json({limit: '100kb'}));

app.post('/api/chat', async (req, res) => {
  const validationError = validateMessages(req.body?.messages);
  if (validationError) return res.status(400).json({error: validationError});

  try {
    const response = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model,
        messages: [{role: 'system', content: systemPrompt}, ...req.body.messages],
        temperature: 0.7,
      }),
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

app.listen(port, () => console.log(`DeepSeek proxy is listening on http://localhost:${port}`));

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
