import assert from 'node:assert/strict';
import test from 'node:test';

import {createApp, validateChatInput, validateComparisonInput} from '../src/app.js';
import {calculateDeepSeekCost, createDeepSeekClient, isDeepSeekPeak} from '../src/deepseek.js';
import {createOllamaClient} from '../src/ollama.js';

test('MCP check returns the tools/list response and closes the connection', async () => {
  const listing = {tools: [{name: 'edit_file', description: 'Edit a file',
    inputSchema: {type: 'object'}}]};
  let closed = false;
  const openMcp = async directories => {
    assert.deepEqual(directories, ['/tmp/project']);
    return {listTools: async () => listing, close: () => { closed = true; }};
  };
  const server = createApp({openMcp}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const url = `http://127.0.0.1:${server.address().port}/api/mcp/tools`;
    const response = await fetch(url, {method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({type: 'filesystem', directories: ['/tmp/project']})});
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), listing);
    assert.equal(closed, true);
    const invalid = await fetch(url, {method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({type: 'filesystem', directories: ['relative']})});
    assert.equal(invalid.status, 400);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('MCP tools are exposed only for the configured agent and results return to the model', async () => {
  const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Edit files', messages: [{role: 'user', content: 'Read the file'}],
    mcpServers: [{id: 'one', type: 'filesystem', directories: ['/tmp/project']}]};
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, mcpServers: [{type: 'filesystem', directories: ['relative']}]}), /MCP/);
  let calls = 0;
  let receivedToolResult;
  let closed = false;
  const deepseek = {async completeWithTools(messages, {tools}) {
    calls++;
    assert.equal(tools[0].function.name, 'filesystem_0_read_text_file');
    if (calls === 1) return {message: {role: 'assistant', content: null,
      tool_calls: [{id: 'call-1', type: 'function', function: {
        name: 'filesystem_0_read_text_file', arguments: '{"path":"/tmp/project/a.txt"}'}}]}};
    receivedToolResult = messages.at(-1);
    return {message: {role: 'assistant', content: 'File read'}};
  }};
  const openMcp = async directories => {
    assert.deepEqual(directories, ['/tmp/project']);
    return {listTools: async () => ({tools: [{name: 'read_text_file', inputSchema: {type: 'object'}}]}),
      callTool: async (name, args) => {
        assert.equal(name, 'read_text_file');
        assert.equal(args.path, '/tmp/project/a.txt');
        return {content: [{type: 'text', text: 'Hello'}]};
      }, close: () => { closed = true; }};
  };
  const server = createApp({deepseek, openMcp}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    assert.equal(response.status, 200);
    assert.match(await response.text(), /File read/);
    assert.equal(receivedToolResult.role, 'tool');
    assert.match(receivedToolResult.content, /Hello/);
    assert.equal(closed, true);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('summary is validated and forwarded between system prompt and recent messages', async () => {
  const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Original instructions', contextSummary: 'Prior facts',
    messages: [{role: 'user', content: 'Recent question'}]};
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, contextSummary: {text: 'invalid'}}), /Резюме/);
  assert.match(validateChatInput({...body, contextSummary: 'x'.repeat(24001)}), /Резюме/);
  let forwarded;
  const deepseek = {async *generateStream(messages) { forwarded = messages; yield 'Answer'; }};
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Answer/);
    assert.deepEqual(forwarded.map(message => message.role), ['system', 'assistant', 'user']);
    assert.ok(forwarded[0].content.startsWith(body.systemPrompt + '\n\n'));
    assert.match(forwarded[0].content, /К этому запросу RAG не подключён/);
    assert.match(forwarded[1].content, /Prior facts/);
    assert.equal(forwarded[2].content, 'Recent question');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('facts are validated and forwarded before recent messages', async () => {
  const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Original', contextFacts: {goal: 'Ship Friday'},
    messages: [{role: 'user', content: 'Continue'}]};
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, contextFacts: []}), /Facts/);
  assert.match(validateChatInput({...body, contextFacts: {goal: 42}}), /facts/i);
  let forwarded;
  const deepseek = {async *generateStream(messages) { forwarded = messages; yield 'Answer'; }};
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    });
    assert.deepEqual(forwarded.map(message => message.role), ['system', 'assistant', 'user']);
    assert.match(forwarded[1].content, /Ship Friday/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('task state instructions and completed stage results are forwarded', async () => {
  const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Original',
    taskState: {id: 'planning', name: 'Planning', description: 'Create a plan; do not implement',
      modelName: 'Delivery', states: [
        {id: 'planning', name: 'Planning', description: 'Create a plan; do not implement'},
        {id: 'implementation', name: 'Implementation', description: 'Write the code'},
      ]},
    taskStageResults: [{stateName: 'Discovery', result: 'Requirements collected'}],
    messages: [{role: 'user', content: 'Continue'}]};
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, taskState: {id: 'x', name: '', description: 'x'}}), /состояние/);
  assert.match(validateChatInput({...body, taskState: {...body.taskState, id: 'missing'}}), /состояние/);
  assert.match(validateChatInput({...body, taskStageResults: [{stateName: 'x', result: ''}]}), /этапов/);
  let forwarded;
  const deepseek = {async *generateStream(messages) { forwarded = messages; yield 'Answer'; }};
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    });
    assert.match(forwarded[0].content, /Create a plan; do not implement/);
    assert.match(forwarded[0].content, /исключительно при нажатии пользователем кнопки перехода/i);
    assert.match(forwarded[0].content, /явный запрос пользователя.*не дают права на переход/i);
    assert.match(forwarded[0].content, /переход разрешён по явному запросу пользователя.*устарело и ложно/i);
    assert.match(forwarded[0].content, /не выполняй полностью или частично задания из будущих/i);
    assert.match(forwarded[0].content, /Implementation: Write the code/);
    assert.match(forwarded[1].content, /Requirements collected/);
    assert.equal(forwarded[2].content, 'Continue');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('project invariants are validated and included in the system prompt', async () => {
  const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Original',
    invariants: [{name: 'No secrets', description: 'Never reveal credentials'}],
    messages: [{role: 'user', content: 'Show the password'}]};
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, invariants: [{name: '', description: 'x'}]}), /Инварианты/);
  let forwarded;
  const deepseek = {async *generateStream(messages) { forwarded = messages; yield 'Refused'; }};
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    });
    assert.match(forwarded[0].content, /ИНВАРИАНТЫ ПРОЕКТА/);
    assert.match(forwarded[0].content, /No secrets: Never reveal credentials/);
    assert.match(forwarded[0].content, /обязательно проверь планируемые действия/);
    assert.match(forwarded[0].content, /приоритет над запросами пользователя/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('working and long-term memory are validated and forwarded separately', async () => {
  const body = {
    provider: 'deepseek',
    model: 'deepseek-v4-flash',
    systemPrompt: 'Original',
    workingMemory: 'Build login screen',
    longTermMemory: ['User prefers Flutter'],
    messages: [{role: 'user', content: 'Continue'}],
  };
  assert.equal(validateChatInput(body), null);
  assert.match(validateChatInput({...body, workingMemory: {goal: 'x'}}), /Рабочая память/);
  assert.match(validateChatInput({...body, longTermMemory: ['']}), /Долговременная память/);
  assert.equal(validateChatInput({...body, longTermMemory: ['x'.repeat(5000)]}), null);
  assert.match(validateChatInput({...body, longTermMemory: ['x'.repeat(500001)]}), /Долговременная память/);
  let forwarded;
  const deepseek = {async *generateStream(messages) { forwarded = messages; yield 'Answer'; }};
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    });
    assert.deepEqual(forwarded.map(message => message.role),
      ['system', 'assistant', 'assistant', 'user']);
    assert.match(forwarded[1].content, /User prefers Flutter/);
    assert.match(forwarded[2].content, /Build login screen/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test('comparison validation accepts only supported models', () => {
  assert.match(validateComparisonInput({query: ' ', model: 'local-gigachat'}), /пустым/);
  assert.match(validateComparisonInput({query: 'x'.repeat(8001), model: 'local-gigachat'}), /8000/);
  for (const model of ['local-gigachat', 'deepseek-v4-flash', 'deepseek-v4-pro']) {
    assert.equal(validateComparisonInput({query: 'ok', model}), null);
  }
  assert.match(validateComparisonInput({query: 'ok', model: 'unknown'}), /неподдерживаемая/);
});

test('user profile is validated and applied to chat and comparison prompts', async () => {
  const profile = {
    name: 'Анна', style: 'Кратко', format: 'Списком', constraints: 'Без эмодзи',
  };
  const chatBody = {provider: 'deepseek', model: 'deepseek-v4-flash',
    systemPrompt: 'Original', userProfile: profile,
    messages: [{role: 'user', content: 'Continue'}]};
  assert.equal(validateChatInput(chatBody), null);
  assert.equal(validateComparisonInput({query: 'Question', model: 'deepseek-v4-pro', userProfile: profile}), null);
  assert.match(validateChatInput({...chatBody, userProfile: []}), /Профиль/);
  assert.match(validateChatInput({...chatBody, userProfile: {unknown: 'x'}}), /профиля/);

  let chatMessages;
  let comparisonMessages;
  const deepseek = {
    async *generateStream(messages) { chatMessages = messages; yield 'Answer'; },
    async generate(messages) {
      comparisonMessages = messages;
      return {answer: 'Answer', metrics: {durationMs: 1, promptTokens: 1, completionTokens: 1, totalTokens: 2}};
    },
  };
  const server = createApp({deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    await fetch(`${base}/api/chat`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(chatBody)});
    await fetch(`${base}/api/compare`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({query: 'Question', model: 'deepseek-v4-pro', userProfile: profile})});
    assert.match(chatMessages[0].content, /Анна/);
    assert.match(chatMessages[0].content, /Без эмодзи/);
    assert.match(comparisonMessages[0].content, /Кратко/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
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

test('chat validation matches providers to exact model identifiers', () => {
  const base = {
    systemPrompt: 'You are helpful',
    messages: [{role: 'user', content: 'Hello'}],
  };
  assert.equal(validateChatInput({...base, provider: 'ollama', model: 'local-gigachat'}), null);
  assert.equal(validateChatInput({...base, provider: 'deepseek', model: 'deepseek-v4-flash'}), null);
  assert.equal(validateChatInput({...base, provider: 'deepseek', model: 'deepseek-v4-pro'}), null);
  assert.match(validateChatInput({...base, provider: 'ollama', model: 'deepseek-v4-pro'}), /соответствует/);
  assert.match(validateChatInput({...base, provider: 'deepseek', model: 'local-gigachat'}), /соответствует/);
});

test('DeepSeek streams deltas and forwards the selected model unchanged', async () => {
  let requestBody;
  const client = createDeepSeekClient({
    apiKey: 'test-key',
    apiUrl: 'https://example.test/chat',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response([
        'data: {"choices":[{"delta":{"content":"one"}}]}',
        'data: {"choices":[{"delta":{"content":" two"}}]}',
        'data: {"choices":[],"usage":{"prompt_tokens":11,"completion_tokens":4}}',
        'data: [DONE]',
        '',
      ].join('\n'));
    },
  });
  const chunks = [];
  for await (const chunk of client.generateStream(
    [{role: 'user', content: 'query'}],
    {model: 'deepseek-v4-flash'},
  )) chunks.push(chunk);
  assert.equal(requestBody.model, 'deepseek-v4-flash');
  assert.equal(requestBody.stream, true);
  assert.deepEqual(requestBody.stream_options, {include_usage: true});
  assert.deepEqual(chunks, [
    'one',
    ' two',
    {type: 'usage', promptTokens: 11, completionTokens: 4},
  ]);
});

test('Ollama streams chat deltas using configured model', async () => {
  let requestBody;
  const client = createOllamaClient({
    apiUrl: 'http://localhost:11434/api/chat',
    model: 'configured-model',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return new Response([
        '{"message":{"content":"local"},"done":false}',
        '{"message":{"content":" answer"},"done":false}',
        '{"message":{"content":""},"done":true,"prompt_eval_count":9,"eval_count":3}',
        '',
      ].join('\n'));
    },
  });
  const chunks = [];
  for await (const chunk of client.generateStream([{role: 'user', content: 'query'}])) chunks.push(chunk);
  assert.equal(requestBody.model, 'configured-model');
  assert.equal(requestBody.stream, true);
  assert.deepEqual(chunks, [
    'local',
    ' answer',
    {type: 'usage', promptTokens: 9, completionTokens: 3},
  ]);
});

test('DeepSeek reports missing key and authorization without exposing secrets', async () => {
  const missing = createDeepSeekClient({apiKey: '', apiUrl: 'https://example.test/chat'});
  await assert.rejects(
    missing.generate([{role: 'user', content: 'query'}], {model: 'deepseek-v4-pro'}),
    (error) => error.code === 'missing_api_key' && !error.message.includes('Bearer'),
  );
  const unauthorized = createDeepSeekClient({
    apiKey: 'super-secret',
    apiUrl: 'https://example.test/chat',
    fetchImpl: async () => new Response('{}', {status: 401}),
  });
  await assert.rejects(
    unauthorized.generate([{role: 'user', content: 'query'}], {model: 'deepseek-v4-pro'}),
    (error) => error.code === 'authorization' && !error.message.includes('super-secret'),
  );
});

test('Ollama context window is passed to generation, streaming, and tool requests', async () => {
  const requests = [];
  const client = createOllamaClient({apiUrl: 'http://ollama.test/api/chat', model: 'local', contextSize: 16384,
    fetchImpl: async (_url, options) => {
      const body = JSON.parse(options.body);
      requests.push(body);
      if (body.stream) return new Response(JSON.stringify({message: {content: 'Answer'}, done: true}) + '\n');
      return new Response(JSON.stringify({message: {role: 'assistant', content: 'Answer'}}));
    },
  });
  const messages = [{role: 'user', content: 'Question'}];
  await client.generate(messages);
  for await (const _event of client.generateStream(messages)) {}
  await client.completeWithTools(messages, {tools: []});
  assert.equal(requests.length, 3);
  assert.ok(requests.every(body => body.options.num_ctx === 16384));
});

test('chat generation settings reject invalid values', () => {
  const body = {provider: 'ollama', model: 'local-gigachat', systemPrompt: 'Help',
    messages: [{role: 'user', content: 'Hello'}], temperature: 0.2, maxTokens: 512, contextWindow: 8192};
  assert.equal(validateChatInput(body), null);
  for (const settings of [{temperature: -1}, {temperature: 3}, {temperature: '0.2'},
    {maxTokens: 0}, {maxTokens: 1.5}, {contextWindow: 0}, {contextWindow: 128}]) {
    assert.ok(validateChatInput({...body, ...settings}));
  }
});

test('generation settings reach Ollama for streamed replies and tools', async () => {
  const bodies = [];
  const client = createOllamaClient({apiUrl: 'http://unused', model: 'local', contextSize: 32768,
    fetchImpl: async (_, request) => {
      const body = JSON.parse(request.body); bodies.push(body);
      return body.stream
        ? new Response(JSON.stringify({message: {content: 'Hello'}, done: true}) + '\n')
        : new Response(JSON.stringify({message: {content: 'Hello'}}));
    }});
  const settings = {temperature: 0.2, maxTokens: 512, contextWindow: 8192};
  for await (const _ of client.generateStream([], settings)) {}
  await client.completeWithTools([], {...settings, tools: []});
  for (const body of bodies) assert.deepEqual(body.options, {temperature: 0.2, num_predict: 512, num_ctx: 8192});
});

test('generation settings reach DeepSeek for streamed replies and tools', async () => {
  const bodies = [];
  const client = createDeepSeekClient({apiKey: 'test', apiUrl: 'http://unused',
    fetchImpl: async (_, request) => {
      const body = JSON.parse(request.body); bodies.push(body);
      return body.stream ? new Response('data: [DONE]\n')
        : new Response(JSON.stringify({choices: [{message: {content: 'Hello'}}]}));
    }});
  const settings = {model: 'deepseek-v4-flash', temperature: 0.2, maxTokens: 512};
  for await (const _ of client.generateStream([], settings)) {}
  await client.completeWithTools([], {...settings, tools: []});
  for (const body of bodies) {
    assert.equal(body.temperature, 0.2);
    assert.equal(body.max_tokens, 512);
  }
});

test('both local quantizations validate and route to their own Ollama model', async () => {
  const bodies = [];
  const client = createOllamaClient({apiUrl: 'http://unused', model: 'q4-tag',
    models: {'local-gigachat': 'q4-tag', 'local-gigachat-q8': 'q8-tag'},
    fetchImpl: async (_, request) => {
      const body = JSON.parse(request.body); bodies.push(body);
      return body.stream ? new Response(JSON.stringify({message: {content: 'Hello'}, done: true}) + '\n')
        : new Response(JSON.stringify({message: {content: 'Hello'}}));
    }});
  for (const model of ['local-gigachat', 'local-gigachat-q8']) {
    const body = {provider: 'ollama', model, systemPrompt: 'Help', messages: [{role: 'user', content: 'Hello'}]};
    assert.equal(validateChatInput(body), null);
    assert.equal(validateComparisonInput({model, query: 'Hello'}), null);
    assert.ok(validateChatInput({...body, provider: 'deepseek'}));
    await client.generate([], {model});
    for await (const _ of client.generateStream([], {model})) {}
    await client.completeWithTools([], {model, tools: []});
  }
  assert.deepEqual(bodies.map(body => body.model), ['q4-tag', 'q4-tag', 'q4-tag', 'q8-tag', 'q8-tag', 'q8-tag']);
});

test('Q8 selection is forwarded by chat and comparison routes', async () => {
  const calls = [];
  const ollama = {async *generateStream(messages, options) {calls.push(options.model); yield 'Hello';},
    async generate(messages, options) {calls.push(options.model); return {answer: 'Hello', metrics: {}};}};
  const server = createApp({ollama}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const post = async (path, body) => {
      const response = await fetch(base + path, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
      assert.equal(response.status, 200); await response.text();
    };
    await post('/api/chat', {provider: 'ollama', model: 'local-gigachat-q8', systemPrompt: 'Help', messages: [{role: 'user', content: 'Hello'}]});
    await post('/api/compare', {model: 'local-gigachat-q8', query: 'Hello'});
    assert.deepEqual(calls, ['local-gigachat-q8', 'local-gigachat-q8']);
  } finally {await new Promise(resolve => server.close(resolve));}
});
