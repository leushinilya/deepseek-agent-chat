export class UpstreamError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
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
    async generate(messages, {model, temperature = 0.7} = {}) {
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
        throw new UpstreamError(timedOut ? 'DeepSeek не успел ответить. Повторите попытку.' : 'Не удалось подключиться к DeepSeek API.', timedOut ? 504 : 502);
      }
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.error('DeepSeek request failed with status', response.status);
        throw new UpstreamError('DeepSeek API временно недоступен. Попробуйте ещё раз.', response.status === 429 ? 429 : 502);
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
  };
}

function numberOrZero(value) {
  return Number.isFinite(value) && value >= 0 ? value : 0;
}
