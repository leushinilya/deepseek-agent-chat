import assert from 'node:assert/strict';
import test from 'node:test';

import {normalizeEvaluations, validateComparisonInput, validateEvaluationInput} from '../src/app.js';
import {createDeepSeekClient, parseJsonObject} from '../src/deepseek.js';

test('comparison validation accepts only supported temperatures', () => {
  assert.match(validateComparisonInput({query: ' ', temperature: 0}), /пустым/);
  assert.match(validateComparisonInput({query: 'x'.repeat(8001), temperature: 0}), /8000/);
  assert.equal(validateComparisonInput({query: 'ok', temperature: 0}), null);
  assert.equal(validateComparisonInput({query: 'ok', temperature: 0.7}), null);
  assert.equal(validateComparisonInput({query: 'ok', temperature: 1.2}), null);
  assert.match(validateComparisonInput({query: 'ok', temperature: 0.5}), /0, 0.7 или 1.2/);
});

test('structured parser accepts fenced JSON and surrounding text', () => {
  assert.deepEqual(parseJsonObject('```json\n{"generatedPrompt":"better"}\n```'), {generatedPrompt: 'better'});
  assert.deepEqual(parseJsonObject('Ответ: {"answers":[]} готов.'), {answers: []});
});

test('DeepSeek client forwards the requested temperature', async () => {
  let requestBody;
  const client = createDeepSeekClient({
    apiKey: 'test-key',
    model: 'test-model',
    apiUrl: 'https://example.test/chat',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response(JSON.stringify({choices: [{message: {content: 'answer'}}]}));
    },
  });

  await client.complete([{role: 'user', content: 'query'}], {temperature: 1.2});
  assert.equal(requestBody.temperature, 1.2);
});

test('evaluation requires three answers for each supported temperature', () => {
  const valid = {
    query: 'query',
    groups: [0, 0.7, 1.2].map((temperature) => ({
      temperature,
      answers: ['one', 'two', 'three'],
    })),
  };
  assert.equal(validateEvaluationInput(valid), null);
  assert.match(validateEvaluationInput({...valid, groups: valid.groups.slice(0, 2)}), /три группы/);
  assert.match(validateEvaluationInput({...valid, groups: valid.groups.map((group) => ({...group, answers: ['one']}))}), /три ответа/);
});

test('evaluation normalization enforces integer scores from 1 to 10', () => {
  const evaluations = [0, 0.7, 1.2].map((temperature) => ({
    temperature,
    accuracy: 8,
    creativity: 7,
    diversity: 6,
    summary: 'Обоснование',
  }));
  assert.deepEqual(normalizeEvaluations(evaluations), evaluations);
  assert.throws(() => normalizeEvaluations(evaluations.map((item) => ({...item, accuracy: 11}))));
});
