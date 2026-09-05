import {UpstreamError} from './deepseek.js';

export function createOllamaClient({apiUrl, model, fetchImpl = fetch}) {
  return {
    async generate(messages) {
      const startedAt = Date.now();
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model, messages, stream: false}),
          signal: AbortSignal.timeout(180000),
        });
      } catch (error) {
        const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(timedOut ? 'Локальная GigaChat 3.1 не успела ответить.' : 'Не удалось подключиться к GigaChat 3.1 на localhost:11434.', timedOut ? 504 : 502);
      }
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.error('Ollama request failed with status', response.status);
        throw new UpstreamError('Локальная GigaChat 3.1 недоступна. Проверьте, что модель загружена и запущена.');
      }
      const answer = payload?.message?.content;
      if (typeof answer !== 'string' || !answer.trim()) throw new UpstreamError('GigaChat 3.1 вернула пустой или некорректный ответ.');
      const promptTokens = numberOrZero(payload.prompt_eval_count);
      const completionTokens = numberOrZero(payload.eval_count);
      return {
        answer: answer.trim(),
        metrics: {
          durationMs: Date.now() - startedAt,
          promptTokens,
          completionTokens,
          totalTokens: promptTokens + completionTokens,
          costUsd: null,
        },
      };
    },
  };
}

function numberOrZero(value) {
  return Number.isFinite(value) && value >= 0 ? value : 0;
}
