export class UpstreamError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.status = status;
  }
}

export function createDeepSeekClient({apiKey, model, apiUrl, fetchImpl = fetch}) {
  return {
    async complete(messages, {json = false, temperature = 0.7} = {}) {
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}`},
          body: JSON.stringify({model, messages, temperature, ...(json ? {response_format: {type: 'json_object'}} : {})}),
          signal: AbortSignal.timeout(60000),
        });
      } catch (error) {
        const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
        throw new UpstreamError(timedOut ? 'Модель не успела ответить. Повторите попытку.' : 'Не удалось подключиться к AI-провайдеру.', timedOut ? 504 : 502);
      }
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.error('AI provider request failed with status', response.status);
        throw new UpstreamError('AI-провайдер временно недоступен. Попробуйте ещё раз.');
      }
      const content = payload?.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || !content.trim()) throw new UpstreamError('AI-провайдер вернул пустой или некорректный ответ.');
      return content.trim();
    },
  };
}

export function parseJsonObject(content) {
  const trimmed = content.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const attempts = [trimmed];
  const firstBrace = trimmed.indexOf('{');
  const lastBrace = trimmed.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) attempts.push(trimmed.slice(firstBrace, lastBrace + 1));
  for (const candidate of attempts) {
    try {
      const value = JSON.parse(candidate);
      if (value && typeof value === 'object' && !Array.isArray(value)) return value;
    } catch (_) {
      // Try the next safe extraction before reporting an invalid response.
    }
  }
  throw new UpstreamError('Модель вернула ответ в неожиданном формате. Попробуйте ещё раз.');
}

export function requiredString(value, field) {
  const result = value?.[field];
  if (typeof result !== 'string' || !result.trim()) throw new UpstreamError(`В ответе модели отсутствует поле ${field}.`);
  return result.trim();
}
