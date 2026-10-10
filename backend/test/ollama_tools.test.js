import assert from 'node:assert/strict';
import test from 'node:test';
import {createOllamaClient} from '../src/ollama.js';

const messages = [{role: 'system', content: 'Текущий этап задачи: Execution.'},
  {role: 'user', content: 'Написать сортировку пузырьком на Kotlin'}];
const native = '<|function_call|>{"name":"Execution","arguments":{"task":"Kotlin"}}';
const answer = '```kotlin\nfun bubbleSort(a: IntArray) {}\n```';

function client(fetchImpl) {
  return createOllamaClient({apiUrl: 'http://unused', model: 'q8', fetchImpl});
}

test('stream hides split native function marker and retries with same model and settings', async () => {
  const requests = [];
  const ollama = client(async (_, request) => {
    const body = JSON.parse(request.body); requests.push(body);
    if (requests.length === 1) {
      return new Response([
        {message: {content: '  <|func'}},
        {message: {content: 'tion_call|>'}},
        {message: {content: '{"name":"Execution","arguments":{"task":"Kotlin"}}'}, done: true,
          prompt_eval_count: 100, eval_count: 20},
      ].map(value => JSON.stringify(value)).join('\n'));
    }
    return new Response(JSON.stringify({message: {content: answer}, prompt_eval_count: 110, eval_count: 50}));
  });
  const events = [];
  for await (const event of ollama.generateStream(messages, {temperature: 0.2, maxTokens: 512, contextWindow: 8192})) events.push(event);
  assert.deepEqual(events, [answer, {type: 'usage', promptTokens: 210, completionTokens: 70}]);
  assert.equal(requests.length, 2);
  assert.equal(requests[1].model, 'q8');
  assert.deepEqual(requests[1].options, requests[0].options);
  assert.match(requests[0].messages[0].content, /Доступные функции: \[\]/);
  assert.match(requests[1].messages[0].content, /Предыдущая попытка/);
  assert.deepEqual(requests[1].messages.slice(1, -1), messages.slice(1));
  assert.deepEqual(requests[1].messages.at(-1), {role: 'available functions', content: '[]'});
});

test('ordinary streaming still emits deltas as they arrive', async () => {
  const ollama = client(async () => new Response([
    {message: {content: 'Привет'}},
    {message: {content: '!'}, done: true},
  ].map(value => JSON.stringify(value)).join('\n') + '\n'));
  const events = [];
  for await (const event of ollama.generateStream(messages)) events.push(event);
  assert.deepEqual(events.slice(0, 2), ['Привет', '!']);
});

test('repeated unavailable call becomes a clear error without leaking the protocol', async () => {
  let count = 0;
  const ollama = client(async () => {count++; return new Response(JSON.stringify({message: {content: native}, done: true}));});
  const events = [];
  await assert.rejects(async () => {
    for await (const event of ollama.generateStream(messages)) events.push(event);
  }, error => error.code === 'unexpected_tool_call');
  assert.deepEqual(events, []);
  assert.equal(count, 2);
});

test('non-streaming replies recover native calls too', async () => {
  let count = 0;
  const ollama = client(async () => new Response(JSON.stringify({message: {content: ++count === 1 ? native : answer}})));
  assert.equal((await ollama.generate(messages)).answer, answer);
  assert.equal(count, 2);
});

test('native calls in tool mode are converted to structured calls for the MCP loop', async () => {
  const tools = [{type: 'function', function: {name: 'rag_search', parameters: {type: 'object'}}}];
  const ollama = client(async (_, request) => {
    const body = JSON.parse(request.body);
    assert.deepEqual(body.tools, tools);
    assert.deepEqual(body.messages.at(-1), {role: 'available functions', content: '["rag_search"]'});
    assert.match(body.messages[0].content, /Доступные функции: \["rag_search"\]/);
    return new Response(JSON.stringify({message: {role: 'assistant', content: '<|function_call|>{"name":"rag_search","arguments":{"query":"Kotlin"}}'}}));
  });
  const result = await ollama.completeWithTools(messages, {tools});
  assert.equal(result.message.content, '');
  assert.deepEqual(result.message.tool_calls, [{function: {name: 'rag_search', arguments: {query: 'Kotlin'}}}]);
});


test('plain chat declares native empty availability and removes old leaked calls from model context', async () => {
  const previous = [...messages, {role: 'assistant', content: native},
    {role: 'user', content: 'перескажи сюжет последних мстителей'}];
  const snapshot = structuredClone(previous);
  const ollama = client(async (_, request) => {
    const body = JSON.parse(request.body);
    assert.deepEqual(body.messages.at(-1), {role: 'available functions', content: '[]'});
    assert.equal(body.messages.filter(message => message.role === 'available functions').length, 1);
    assert.equal(body.messages.some(message => message.content === native), false);
    assert.equal(body.messages.at(-2).content, previous.at(-1).content);
    return new Response(JSON.stringify({message: {content: 'Сюжет фильма'}, done: true}));
  });
  assert.equal((await ollama.generate(previous)).answer, 'Сюжет фильма');
  assert.deepEqual(previous, snapshot);
});
