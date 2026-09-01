import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildDeepSeekRequest,
  buildSystemPrompt,
  defaultSettings,
  parseSettings,
} from '../src/server.js';

test('uses defaults when settings are omitted', () => {
  assert.deepEqual(parseSettings(undefined), {value: {...defaultSettings}});
});

test('accepts and normalizes valid settings', () => {
  assert.deepEqual(
    parseSettings({responseFormat: 'json', maxTokens: 4000, stopSequence: 'END'}),
    {value: {responseFormat: 'json', maxTokens: 4000, stopSequence: 'END'}},
  );
  assert.equal(
    parseSettings({responseFormat: 'freeform', maxTokens: 50, stopSequence: '  '}).value.stopSequence,
    null,
  );
});

test('rejects invalid settings', () => {
  assert.match(parseSettings(null).error, /объектом/);
  assert.match(parseSettings({responseFormat: 'xml'}).error, /freeform или json/);
  assert.match(parseSettings({maxTokens: 49}).error, /от 50 до 4000/);
  assert.match(parseSettings({maxTokens: 100.5}).error, /целым числом/);
  assert.match(parseSettings({stopSequence: 'x'.repeat(101)}).error, /100 символов/);
});

test('builds JSON prompt and forwards max_tokens and stop', () => {
  const settings = {responseFormat: 'json', maxTokens: 750, stopSequence: 'DONE'};
  const request = buildDeepSeekRequest([{role: 'user', content: 'Hello'}], settings);

  assert.equal(request.max_tokens, 750);
  assert.equal(request.stop, 'DONE');
  assert.match(request.messages[0].content, /корректный JSON/);
});

test('omits stop for freeform requests without a sequence', () => {
  const request = buildDeepSeekRequest([], defaultSettings);

  assert.equal('stop' in request, false);
  assert.equal(buildSystemPrompt(defaultSettings).includes('JSON'), false);
});
