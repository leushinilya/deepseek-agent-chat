import assert from 'node:assert/strict';
import test from 'node:test';

import {validateComparisonInput} from '../src/app.js';
import {calculateDeepSeekCost, createDeepSeekClient, isDeepSeekPeak} from '../src/deepseek.js';
import {createOllamaClient} from '../src/ollama.js';

test('comparison validation accepts only supported models', () => {
  assert.match(validateComparisonInput({query: ' ', model: 'local-gigachat'}), /пустым/);
  assert.match(validateComparisonInput({query: 'x'.repeat(8001), model: 'local-gigachat'}), /8000/);
  for (const model of ['local-gigachat', 'deepseek-v4-flash', 'deepseek-v4-pro']) {
    assert.equal(validateComparisonInput({query: 'ok', model}), null);
  }
  assert.match(validateComparisonInput({query: 'ok', model: 'unknown'}), /неподдерживаемая/);
});

test('DeepSeek client forwards model and returns usage metrics', async () => {
  let requestBody;
  const client = createDeepSeekClient({
    apiKey: 'test-key',
    apiUrl: 'https://example.test/chat',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(JSON.stringify({
        choices: [{message: {content: 'answer'}}],
        usage: {prompt_tokens: 100, completion_tokens: 50, total_tokens: 150},
      }));
    },
  });
  const result = await client.generate([{role: 'user', content: 'query'}], {model: 'deepseek-v4-pro'});
  assert.equal(requestBody.model, 'deepseek-v4-pro');
  assert.equal(result.metrics.totalTokens, 150);
  assert.ok(result.metrics.costUsd > 0);
});

test('DeepSeek pricing accounts for peak hours and cache hits', () => {
  const usage = {prompt_tokens: 1000, prompt_cache_hit_tokens: 500, completion_tokens: 1000};
  const peak = new Date('2026-09-04T02:00:00Z');
  const offPeak = new Date('2026-09-05T02:00:00Z');
  assert.equal(isDeepSeekPeak(peak), true);
  assert.equal(isDeepSeekPeak(offPeak), false);
  assert.equal(calculateDeepSeekCost('deepseek-v4-flash', usage, peak), 0.001547);
  assert.equal(calculateDeepSeekCost('deepseek-v4-flash', usage, offPeak), 0.0007735);
});

test('Ollama client uses local chat format and reports free usage', async () => {
  let requestBody;
  const client = createOllamaClient({
    apiUrl: 'http://localhost:11434/api/chat',
    model: 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(JSON.stringify({message: {content: 'local answer'}, prompt_eval_count: 12, eval_count: 8}));
    },
  });
  const result = await client.generate([{role: 'user', content: 'query'}]);
  assert.equal(requestBody.stream, false);
  assert.equal(requestBody.model, 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M');
  assert.equal(result.metrics.totalTokens, 20);
  assert.equal(result.metrics.costUsd, null);
});
