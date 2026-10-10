import {UpstreamError} from './deepseek.js';

export function createOllamaClient({apiUrl, model, contextSize = 32768, fetchImpl = fetch}) {
  return {
    async completeWithTools(messages, {tools, signal}) {
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model, messages, tools, options: {num_ctx: contextSize}, stream: false}),
          signal: signal ?? AbortSignal.timeout(180000),
        });
      } catch {
        throw new UpstreamError('Не удалось подключиться к Ollama.', 502, 'ollama_unavailable');
      }
      if (!response.ok) throw new UpstreamError('Ollama не смогла вызвать инструменты.', 502);
      const payload = await response.json();
      if (!payload?.message) throw new UpstreamError('Ollama вернула некорректный ответ.');
      return {message: payload.message,
        usage: {prompt_tokens: payload.prompt_eval_count, completion_tokens: payload.eval_count}};
    },
    async generate(messages, {signal, temperature = 0.7} = {}) {
      const startedAt = Date.now();
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model, messages, options: {temperature, num_ctx: contextSize}, stream: false}),
          signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(180000)]) : AbortSignal.timeout(180000),
        });
      } catch (error) {
        const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(timedOut ? 'Локальная GigaChat 3.1 не успела ответить.' : 'Не удалось подключиться к Ollama. Проверьте адрес и запуск сервиса.', timedOut ? 504 : 502, timedOut ? 'timeout' : 'ollama_unavailable');
      }
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.error('Ollama request failed with status', response.status);
        throw new UpstreamError('Локальная модель не установлена или недоступна в Ollama.', 502, 'model_not_installed');
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
    async *generateStream(messages, {signal} = {}) {
      const timeout = timeoutSignal(signal);
      try {
        const response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model, messages, options: {num_ctx: contextSize}, stream: true}),
          signal: timeout.signal,
        });
        if (!response.ok) {
          throw new UpstreamError('Локальная модель не установлена или недоступна в Ollama.', 502, 'model_not_installed');
        }
        if (!response.body) throw new UpstreamError('Ollama вернула некорректный поток данных.', 502, 'invalid_response');
        let buffer = '';
        const decoder = new TextDecoder();
        for await (const chunk of response.body) {
          buffer += decoder.decode(chunk, {stream: true});
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';
          for (const line of lines) {
            if (!line.trim()) continue;
            let payload;
            try {
              payload = JSON.parse(line);
            } catch {
              throw new UpstreamError('Ollama вернула некорректный поток данных.', 502, 'invalid_response');
            }
            const text = payload?.message?.content;
            if (typeof text === 'string' && text) yield text;
            if (payload?.done === true) {
              yield {
                type: 'usage',
                promptTokens: numberOrZero(payload.prompt_eval_count),
                completionTokens: numberOrZero(payload.eval_count),
              };
              return;
            }
          }
        }
        if (buffer.trim()) {
          try {
            const payload = JSON.parse(buffer);
            const text = payload?.message?.content;
            if (typeof text === 'string' && text) yield text;
            if (payload?.done === true) {
              yield {
                type: 'usage',
                promptTokens: numberOrZero(payload.prompt_eval_count),
                completionTokens: numberOrZero(payload.eval_count),
              };
              return;
            }
          } catch {
            throw new UpstreamError('Ollama вернула некорректный поток данных.', 502, 'invalid_response');
          }
        }
        throw new UpstreamError('Ollama завершила поток без признака окончания.', 502, 'invalid_response');
      } catch (error) {
        if (error instanceof UpstreamError) throw error;
        const aborted = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(aborted ? 'Генерация локальной модели была остановлена или превысила тайм-аут.' : 'Не удалось подключиться к Ollama. Проверьте адрес и запуск сервиса.', aborted ? 504 : 502, aborted ? 'timeout' : 'ollama_unavailable');
      } finally {
        timeout.clear();
      }
    },
  };
}

function timeoutSignal(externalSignal) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 180000);
  const abort = () => controller.abort();
  externalSignal?.addEventListener('abort', abort, {once: true});
  return {
    signal: controller.signal,
    clear() {
      clearTimeout(timer);
      externalSignal?.removeEventListener('abort', abort);
    },
  };
}

function numberOrZero(value) {
  return Number.isFinite(value) && value >= 0 ? value : 0;
}
