import {UpstreamError} from './deepseek.js';

export function createOllamaClient({apiUrl, model, contextSize = 32768, models = {}, fetchImpl = fetch}) {
  const resolveModel = requested => {
    if (requested === undefined) return model;
    if (Object.hasOwn(models, requested)) return models[requested];
    if (requested === 'local-gigachat') return model;
    if (requested === model) return model;
    throw new UpstreamError('Локальная модель не настроена.', 400, 'unsupported_model');
  };
  return {
    async completeWithTools(messages, {tools, signal, temperature = 0.7, maxTokens, contextWindow, model: requestedModel}) {
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model: resolveModel(requestedModel), messages: withToolAvailability(messages, tools), tools, options: {temperature, num_ctx: contextWindow ?? contextSize, ...(maxTokens !== undefined ? {num_predict: maxTokens} : {})}, stream: false}),
          signal: signal ?? AbortSignal.timeout(180000),
        });
      } catch {
        throw new UpstreamError('Не удалось подключиться к Ollama.', 502, 'ollama_unavailable');
      }
      if (!response.ok) throw new UpstreamError('Ollama не смогла вызвать инструменты.', 502);
      const payload = await response.json();
      if (!payload?.message) throw new UpstreamError('Ollama вернула некорректный ответ.');
      return {message: normalizeToolMessage(payload.message),
        usage: {prompt_tokens: payload.prompt_eval_count, completion_tokens: payload.eval_count}};
    },
    async generate(messages, {signal, temperature = 0.7, maxTokens, contextWindow, model: requestedModel, retryToolCall = true} = {}) {
      const startedAt = Date.now();
      let response;
      try {
        response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model: resolveModel(requestedModel), messages: withToolAvailability(messages), options: {temperature, num_ctx: contextWindow ?? contextSize, ...(maxTokens !== undefined ? {num_predict: maxTokens} : {})}, stream: false}),
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
      if (isNativeToolCall(answer ?? '') || payload?.message?.tool_calls?.length) {
        if (!retryToolCall) throw unexpectedToolCall();
        const recovered = await this.generate(withToolAvailability(messages, [], true),
          {signal, temperature, maxTokens, contextWindow, model: requestedModel, retryToolCall: false});
        recovered.metrics.promptTokens += numberOrZero(payload.prompt_eval_count);
        recovered.metrics.completionTokens += numberOrZero(payload.eval_count);
        recovered.metrics.totalTokens = recovered.metrics.promptTokens + recovered.metrics.completionTokens;
        recovered.metrics.durationMs = Date.now() - startedAt;
        return recovered;
      }
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
    async *generateStream(messages, {signal, temperature = 0.7, maxTokens, contextWindow, model: requestedModel} = {}) {
      const timeout = timeoutSignal(signal);
      try {
        const response = await fetchImpl(apiUrl, {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({model: resolveModel(requestedModel), messages: withToolAvailability(messages), options: {temperature, num_ctx: contextWindow ?? contextSize, ...(maxTokens !== undefined ? {num_predict: maxTokens} : {})}, stream: true}),
          signal: timeout.signal,
        });
        if (!response.ok) {
          throw new UpstreamError('Локальная модель не установлена или недоступна в Ollama.', 502, 'model_not_installed');
        }
        if (!response.body) throw new UpstreamError('Ollama вернула некорректный поток данных.', 502, 'invalid_response');
        let prefix = '';
        let ordinaryText = false;
        let nativeCall = false;
        for await (const payload of readOllamaStream(response.body)) {
          const text = payload?.message?.content;
          if (payload?.message?.tool_calls?.length) nativeCall = true;
          if (typeof text === 'string' && text && !nativeCall) {
            if (ordinaryText) {
              yield text;
            } else {
              prefix += text;
              if (isNativeToolCall(prefix)) {
                nativeCall = true;
                prefix = '';
              } else if (prefix.trimStart() && !FUNCTION_CALL.startsWith(prefix.trimStart())) {
                ordinaryText = true;
                yield prefix;
                prefix = '';
              }
            }
          }
          if (payload?.done === true) {
            let promptTokens = numberOrZero(payload.prompt_eval_count);
            let completionTokens = numberOrZero(payload.eval_count);
            if (nativeCall) {
              const recovered = await this.generate(withToolAvailability(messages, [], true),
                {signal: timeout.signal, temperature, maxTokens, contextWindow, model: requestedModel, retryToolCall: false});
              yield recovered.answer;
              promptTokens += recovered.metrics.promptTokens;
              completionTokens += recovered.metrics.completionTokens;
            } else if (prefix) {
              yield prefix;
            }
            yield {type: 'usage', promptTokens, completionTokens};
            return;
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

const FUNCTION_CALL = '<|function_call|>';

function isNativeToolCall(text) {
  return text.trimStart().startsWith(FUNCTION_CALL);
}

function unexpectedToolCall() {
  return new UpstreamError('Модель повторно вызвала недоступный инструмент вместо ответа. Попробуйте повторить запрос.',
    502, 'unexpected_tool_call');
}

function withToolAvailability(messages, tools = [], retry = false) {
  const names = tools.map(tool => tool.function.name);
  const instruction = names.length
    ? `Доступные функции: ${JSON.stringify(names)}. Вызывай только эти функции. Названия этапов задачи не являются функциями.`
    : 'Доступные функции: []. Инструментов в этом запросе нет. Названия этапов задачи (например, Execution) не являются функциями. Выполни запрос самостоятельно и верни ответ пользователю обычным текстом или кодом. Не генерируй вызовы функций.';
  const addition = '\n\n' + instruction + (retry
    ? '\nПредыдущая попытка вернула служебный вызов недоступной функции. Вместо вызова напиши сам ответ на последний запрос пользователя.' : '');
  // GigaChat's native template expects this role, separately from system instructions.
  // Old leaked calls were never executed and must not become examples for later replies.
  const history = messages.filter(message => message.role !== 'available functions' &&
    !(names.length === 0 && message.role === 'assistant' && isNativeToolCall(message.content ?? '')));
  const prepared = history[0]?.role === 'system'
    ? [{...history[0], content: history[0].content + addition}, ...history.slice(1)]
    : [{role: 'system', content: instruction + addition}, ...history];
  return [...prepared, {role: 'available functions', content: JSON.stringify(names)}];
}

function normalizeToolMessage(message) {
  if (message.tool_calls?.length || !isNativeToolCall(message.content ?? '')) return message;
  let call;
  try {call = JSON.parse(message.content.trimStart().slice(FUNCTION_CALL.length));}
  catch {throw new UpstreamError('Модель вернула некорректный вызов инструмента.', 502, 'invalid_tool_call');}
  if (typeof call.name !== 'string' || !call.arguments || typeof call.arguments !== 'object' || Array.isArray(call.arguments)) {
    throw new UpstreamError('Модель вернула некорректный вызов инструмента.', 502, 'invalid_tool_call');
  }
  return {...message, content: '', tool_calls: [{function: {name: call.name, arguments: call.arguments}}]};
}

async function* readOllamaStream(body) {
  let buffer = '';
  const decoder = new TextDecoder();
  const parse = line => {
    try {return JSON.parse(line);}
    catch {throw new UpstreamError('Ollama вернула некорректный поток данных.', 502, 'invalid_response');}
  };
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, {stream: true});
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) if (line.trim()) yield parse(line);
  }
  buffer += decoder.decode();
  if (buffer.trim()) yield parse(buffer);
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
