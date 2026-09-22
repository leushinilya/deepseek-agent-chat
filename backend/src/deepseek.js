export class UpstreamError extends Error {
  constructor(message, status = 502, code = 'provider_error') {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const prices = Object.freeze({
  'deepseek-v4-flash': Object.freeze({
    offPeak: {cacheHit: 0.007, cacheMiss: 0.22, output: 0.66},
    peak: {cacheHit: 0.014, cacheMiss: 0.44, output: 1.32},
  }),
  'deepseek-v4-pro': Object.freeze({
    offPeak: {cacheHit: 0.022, cacheMiss: 0.66, output: 1.98},
    peak: {cacheHit: 0.044, cacheMiss: 1.32, output: 3.96},
  }),
});

export function isDeepSeekPeak(date = new Date()) {
  const day = date.getUTCDay();
  const hour = date.getUTCHours();
  return day >= 1 && day <= 5 && ((hour >= 1 && hour < 4) || (hour >= 6 && hour < 10));
}

export function calculateDeepSeekCost(model, usage, date = new Date()) {
  const modelPrices = prices[model];
  if (!modelPrices) throw new Error(`Pricing is not configured for ${model}.`);
  const rate = isDeepSeekPeak(date) ? modelPrices.peak : modelPrices.offPeak;
  const promptTokens = numberOrZero(usage?.prompt_tokens);
  const cachedTokens = Math.min(promptTokens, numberOrZero(usage?.prompt_cache_hit_tokens));
  const uncachedTokens = promptTokens - cachedTokens;
  const completionTokens = numberOrZero(usage?.completion_tokens);
  return (cachedTokens * rate.cacheHit + uncachedTokens * rate.cacheMiss + completionTokens * rate.output) / 1_000_000;
}

export function createDeepSeekClient({apiKey, apiUrl, fetchImpl = fetch}) {
  return {
    async completeWithTools(messages, {model, tools, signal}) {
      ensureApiKey(apiKey);
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}`},
          body: JSON.stringify({model, messages, tools, stream: false}),
          signal: signal ?? AbortSignal.timeout(180000),
        });
      } catch {
        throw new UpstreamError('Не удалось подключиться к DeepSeek API.', 502, 'network_error');
      }
      if (!response.ok) throw deepSeekStatusError(response.status);
      const payload = await response.json();
      const message = payload?.choices?.[0]?.message;
      if (!message) throw new UpstreamError('DeepSeek вернул некорректный ответ.');
      return {message, usage: payload.usage};
    },
    async generate(messages, {model, temperature = 0.7} = {}) {
      ensureApiKey(apiKey);
      const startedAt = Date.now();
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}`},
          body: JSON.stringify({model, messages, temperature, stream: false}),
          signal: AbortSignal.timeout(180000),
        });
      } catch (error) {
        const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(timedOut ? 'DeepSeek не успел ответить. Повторите попытку.' : 'Не удалось подключиться к DeepSeek API.', timedOut ? 504 : 502, timedOut ? 'timeout' : 'network_error');
      }
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.error('DeepSeek request failed with status', response.status);
        throw deepSeekStatusError(response.status);
      }
      const answer = payload?.choices?.[0]?.message?.content;
      if (typeof answer !== 'string' || !answer.trim()) throw new UpstreamError('DeepSeek вернул пустой или некорректный ответ.');
      const usage = payload?.usage ?? {};
      const promptTokens = numberOrZero(usage.prompt_tokens);
      const completionTokens = numberOrZero(usage.completion_tokens);
      return {
        answer: answer.trim(),
        metrics: {
          durationMs: Date.now() - startedAt,
          promptTokens,
          completionTokens,
          totalTokens: numberOrZero(usage.total_tokens) || promptTokens + completionTokens,
          costUsd: calculateDeepSeekCost(model, usage),
        },
      };
    },
    async *generateStream(messages, {model, temperature = 0.7, signal} = {}) {
      ensureApiKey(apiKey);
      const timeout = timeoutSignal(signal);
      try {
        const response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}`},
          body: JSON.stringify({
            model,
            messages,
            temperature,
            stream: true,
            stream_options: {include_usage: true},
          }),
          signal: timeout.signal,
        });
        if (!response.ok) throw deepSeekStatusError(response.status);
        if (!response.body) throw new UpstreamError('DeepSeek вернул некорректный поток данных.', 502, 'invalid_response');

        let buffer = '';
        const decoder = new TextDecoder();
        for await (const chunk of response.body) {
          buffer += decoder.decode(chunk, {stream: true});
          const lines = buffer.split('\n');
          buffer = lines.pop() ?? '';
          for (const rawLine of lines) {
            const line = rawLine.trim();
            if (!line.startsWith('data:')) continue;
            const data = line.slice(5).trim();
            if (data === '[DONE]') return;
            let payload;
            try {
              payload = JSON.parse(data);
            } catch {
              throw new UpstreamError('DeepSeek вернул некорректный поток данных.', 502, 'invalid_response');
            }
            const text = payload?.choices?.[0]?.delta?.content;
            if (typeof text === 'string' && text) yield text;
            if (payload?.usage) {
              yield {
                type: 'usage',
                promptTokens: numberOrZero(payload.usage.prompt_tokens),
                completionTokens: numberOrZero(payload.usage.completion_tokens),
              };
            }
          }
        }
        throw new UpstreamError('DeepSeek завершил поток без признака окончания.', 502, 'invalid_response');
      } catch (error) {
        if (error instanceof UpstreamError) throw error;
        const aborted = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(aborted ? 'Генерация DeepSeek была остановлена или превысила тайм-аут.' : 'Не удалось подключиться к DeepSeek API.', aborted ? 504 : 502, aborted ? 'timeout' : 'network_error');
      } finally {
        timeout.clear();
      }
    },
  };
}

function ensureApiKey(apiKey) {
  if (!apiKey) throw new UpstreamError('DeepSeek API не настроен: отсутствует API-ключ на сервере.', 503, 'missing_api_key');
}

function deepSeekStatusError(status) {
  if (status === 401 || status === 403) return new UpstreamError('DeepSeek отклонил авторизацию. Проверьте API-ключ на сервере.', 502, 'authorization');
  if (status === 429) return new UpstreamError('Превышен лимит запросов DeepSeek. Повторите попытку позже.', 429, 'rate_limit');
  return new UpstreamError('DeepSeek API временно недоступен. Попробуйте ещё раз.', 502, 'provider_error');
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
