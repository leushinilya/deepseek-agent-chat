import assert from 'node:assert/strict';
import test from 'node:test';

import {normalizeRoles, validateComparisonInput} from '../src/app.js';
import {parseJsonObject} from '../src/deepseek.js';

test('normalizeRoles trims and removes blank role values', () => {
  assert.deepEqual(normalizeRoles([' учёный ', '', '  ', 'врач']), ['учёный', 'врач']);
});

test('comparison validation rejects empty and oversized input', () => {
  assert.match(validateComparisonInput({query: ' '}, 'direct'), /пустым/);
  assert.match(validateComparisonInput({query: 'x'.repeat(8001)}, 'direct'), /8000/);
  assert.match(validateComparisonInput({query: 'ok', roles: []}, 'roles'), /хотя бы одну/);
  assert.match(validateComparisonInput({query: 'ok', roles: Array(11).fill('role')}, 'roles'), /10/);
});

test('structured parser accepts fenced JSON and surrounding text', () => {
  assert.deepEqual(parseJsonObject('```json\n{"generatedPrompt":"better"}\n```'), {generatedPrompt: 'better'});
  assert.deepEqual(parseJsonObject('Ответ: {"answers":[]} готов.'), {answers: []});
});
