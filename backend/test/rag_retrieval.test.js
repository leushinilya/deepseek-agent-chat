import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';

import {createApp} from '../src/app.js';
import {RagStore, defaultRetrievalSettings} from '../src/rag.js';
import {rewriteRagQuery, ragPromptMessages} from '../src/rag_pipeline.js';

async function fixture() {
  const directory = mkdtempSync(join(tmpdir(), 'rag-retrieval-'));
  const path = join(directory, 'rag.sqlite');
  const embed = async texts => texts.map(text => {
    if (text.includes('unrelated')) return [0.6, -0.8];
    if (text.includes('near')) return [0.8, 0.6];
    if (text.includes('Alpha')) return [1, 0];
    return [0, 1];
  });
  const store = new RagStore({path, embed});
  const rag = store.create('Knowledge', [
    {name: 'alpha.txt', content: 'Alpha price: 100'},
    {name: 'near.txt', content: 'near Alpha: background'},
    {name: 'beta.txt', content: 'Beta price: 200'},
  ]);
  store.startIndex(rag.id, 'fixed');
  while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
  return {directory, path, store, rag, embed};
}

async function withServer(store, clients, callback) {
  const server = createApp({ragStore: store, ...clients}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally { await new Promise(resolve => server.close(resolve)); }
}

function jsonRequest(method, body) {
  return {method, headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)};
}

test('retrieval applies candidate K, inclusive threshold, final K, and permits an empty result', async () => {
  const {store, rag, directory} = await fixture();
  try {
    store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false,
      candidateK: 2, resultK: 2, similarityThreshold: 0.8});
    const found = await store.retrieve([rag.id], 'Alpha');
    assert.deepEqual(found.chunks.map(chunk => chunk.source), ['alpha.txt', 'near.txt']);
    assert.equal(found.searches[0].candidateCount, 2);
    store.updateSettings(rag.id, {...store.get(rag.id).retrievalSettings, resultK: 1});
    assert.equal((await store.retrieve([rag.id], 'Alpha')).chunks.length, 1);
    store.updateSettings(rag.id, {...store.get(rag.id).retrievalSettings, similarityThreshold: 0.99});
    const empty = await store.retrieve([rag.id], 'unrelated question');
    assert.equal(empty.chunks.length, 0);
    assert.equal(empty.searches[0].relevantCount, 0);
    const baseline = await store.retrieve([rag.id], 'unrelated question', {baseline: true});
    assert.equal(baseline.chunks.length, 3);
    assert.equal(baseline.rewrittenQuery, null);
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('multiple RAGs use their own settings and one shared rewrite; settings survive reopening', async () => {
  const {store, rag, directory, path, embed} = await fixture();
  let reopened;
  try {
    const second = store.create('Second', [{name: 'beta.txt', content: 'Beta price: 200'}]);
    store.startIndex(second.id, 'fixed');
    while (store.get(second.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    const settings = {...defaultRetrievalSettings, prompt: 'Use tables', rewriteEnabled: false, candidateK: 1, resultK: 1};
    store.updateSettings(second.id, settings);
    let calls = 0;
    const found = await store.retrieve([rag.id, second.id], 'What is its price?', {
      rewrite: async query => { calls++; assert.equal(query, 'What is its price?'); return 'Alpha price'; },
    });
    assert.equal(calls, 1);
    assert.deepEqual(found.searches.map(search => search.query), ['Alpha price', 'What is its price?']);
    assert.ok(found.chunks.some(chunk => chunk.ragId === second.id));
    reopened = new RagStore({path, embed});
    assert.deepEqual(reopened.get(second.id).retrievalSettings, settings);
    assert.deepEqual(reopened.list().find(item => item.id === second.id).retrievalSettings, settings);
  } finally { reopened?.close(); store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('existing SQLite databases migrate without losing documents', () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-migrate-'));
  const path = join(directory, 'rag.sqlite');
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE rags (id TEXT PRIMARY KEY, name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ready', strategy TEXT, error TEXT,
    chunk_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
    INSERT INTO rags (id, name, created_at) VALUES ('old', 'Existing', '2026-01-01');`);
  db.close();
  const store = new RagStore({path, embed: async () => []});
  try {
    assert.equal(store.get('old').name, 'Existing');
    assert.deepEqual(store.get('old').retrievalSettings, defaultRetrievalSettings);
    assert.equal(store.list().length, 1);
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('settings API validates limits and comparison uses identical agent model and original question', async () => {
  const {store, rag, directory} = await fixture();
  const calls = [];
  const deepseek = {async completeWithTools(messages, options) {
    const result = await this.generate(messages, {...options, temperature: 0});
    return {message: {role: 'assistant', content: result.answer}};
  }, async generate(messages, options) {
    calls.push({messages, options});
    return {answer: messages[0].content.startsWith('Переформулируй') ? 'Alpha price' : '100, alpha.txt',
      metrics: {promptTokens: 10, completionTokens: 4}};
  }};
  try {
    await withServer(store, {deepseek}, async base => {
      for (const invalid of [null, {...defaultRetrievalSettings, prompt: 123},
        {...defaultRetrievalSettings, prompt: 'x'.repeat(10001)}, {...defaultRetrievalSettings, candidateK: 0},
        {...defaultRetrievalSettings, resultK: 21}, {...defaultRetrievalSettings, similarityThreshold: 2},
        {...defaultRetrievalSettings, rewriteEnabled: 'yes'}, {...defaultRetrievalSettings, resultK: 1.5},
        {...defaultRetrievalSettings, neighborRadius: 3},
        {...defaultRetrievalSettings, maxExpansionCalls: 6},
        {...defaultRetrievalSettings, maxSearchCalls: 6},
        {...defaultRetrievalSettings, maxContextChars: 999}]) {
        assert.equal((await fetch(`${base}/api/rags/${rag.id}/retrieval`, jsonRequest('PATCH', invalid))).status, 400);
      }
      const settings = {...defaultRetrievalSettings, prompt: 'Cite numbered paragraphs', similarityThreshold: 0.9,
        resultK: 2, maxSearchCalls: 0};
      const response = await fetch(`${base}/api/rags/${rag.id}/retrieval`, jsonRequest('PATCH', settings));
      assert.deepEqual((await response.json()).retrievalSettings, settings);
      assert.equal((await fetch(`${base}/api/rags/missing/retrieval`, jsonRequest('PATCH', settings))).status, 404);
      const comparisonSettings = {...settings, filterEnabled: false,
        neighborRadius: 0, maxExpansionCalls: 0, maxSearchCalls: 0};
      const input = {query: 'What is its price?', provider: 'deepseek',
        model: 'deepseek-v4-pro', systemPrompt: 'Answer with citations',
        retrievalSettings: comparisonSettings};
      assert.equal((await fetch(`${base}/api/rags/${rag.id}/compare`, jsonRequest('POST',
        {...input, retrievalSettings: {...comparisonSettings, neighborRadius: 3}}))).status, 400);
      const comparison = await fetch(`${base}/api/rags/${rag.id}/compare`, jsonRequest('POST', input));
      assert.equal(comparison.status, 200);
      const result = await comparison.json();
      assert.equal(result.baseline.chunks.length, 3);
      assert.equal(result.improved.chunks.length, 2);
      assert.deepEqual(result.improved.settingsByRag[rag.id], comparisonSettings);
      assert.deepEqual(store.get(rag.id).retrievalSettings, settings);
      assert.equal(result.baseline.rewrittenQuery, null);
      assert.equal(result.improved.rewrittenQuery, 'Alpha price');
      assert.equal(calls.length, 3);
      assert.ok(calls.every(call => call.options.model === 'deepseek-v4-pro' && call.options.temperature === 0));
      for (const answerCall of [calls[0], calls[2]]) {
        assert.equal(answerCall.messages.at(-1).content, input.query);
        assert.equal(answerCall.messages[0].content, input.systemPrompt);
        assert.equal(answerCall.messages[1].role, 'system');
        assert.match(answerCall.messages[1].content, /Cite numbered paragraphs/);
      }
      assert.equal((await fetch(`${base}/api/rags/${rag.id}/compare`, jsonRequest('POST', {...input, provider: 'ollama'}))).status, 400);
    });
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('rewrite uses context, selected model, and rejects invalid output', async () => {
  let received;
  const client = {async generate(messages, options) {
    received = {messages, options}; return {answer: '  Alpha price  '};
  }};
  const history = [{role: 'user', content: 'Tell me about Alpha'},
    {role: 'assistant', content: 'Alpha is a product'}, {role: 'user', content: 'What is its price?'}];
  assert.equal(await rewriteRagQuery(client, 'deepseek-v4-pro', history,
    {contextSummary: 'Alpha', contextFacts: {product: 'Alpha'}}), 'Alpha price');
  assert.equal(received.options.model, 'deepseek-v4-pro');
  assert.equal(received.options.temperature, 0);
  assert.deepEqual(received.messages.slice(-3), history);
  assert.match(received.messages[1].content, /Alpha/);
  await assert.rejects(() => rewriteRagQuery({generate: async () => ({answer: ''})}, 'model', history));
  await assert.rejects(() => rewriteRagQuery({generate: async () => ({answer: 'x'.repeat(4001)})}, 'model', history));
});

test('Ollama performs rewrite and chat with no irrelevant context when filtering rejects every chunk', async () => {
  const {store, rag, directory} = await fixture();
  let rewriteCalls = 0;
  let answered;
  const ollama = {
    async completeWithTools(messages) { answered = messages; return {message: {role: 'assistant', content: 'Недостаточно данных'}}; },
    async generate(messages) { rewriteCalls++; return {answer: 'unrelated question'}; },
    async *generateStream(messages) { answered = messages; yield 'Недостаточно данных'; },
  };
  try {
    store.updateSettings(rag.id, {...defaultRetrievalSettings, prompt: 'Answer in Russian', similarityThreshold: 0.99,
      maxSearchCalls: 0});
    await withServer(store, {ollama}, async base => {
      const response = await fetch(`${base}/api/chat`, jsonRequest('POST', {
        provider: 'ollama', model: 'local-gigachat', systemPrompt: 'Answer', ragIds: [rag.id],
        messages: [{role: 'user', content: 'Question'}],
      }));
      assert.equal(response.status, 200);
      const events = (await response.text()).trim().split('\n').map(JSON.parse);
      assert.equal(events[0].rewrittenQuery, 'unrelated question');
      assert.equal(events[0].searches[0].selectedCount, 0);
      assert.equal(rewriteCalls, 1);
      assert.equal(answered[1].role, 'system');
      assert.match(answered[1].content, /Answer in Russian/);
      assert.match(answered[2].content, /Первый поиск не нашёл релевантных фрагментов/);
      assert.doesNotMatch(answered[2].content, /Alpha price|Beta price/);
      assert.equal(answered.at(-1).content, 'Question');
      store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false,
        filterEnabled: false, maxSearchCalls: 0});
      const second = await fetch(`${base}/api/chat`, jsonRequest('POST', {
        provider: 'ollama', model: 'local-gigachat', systemPrompt: 'Answer', ragIds: [rag.id],
        messages: [{role: 'user', content: 'Question'}],
      }));
      await second.text();
      assert.equal(rewriteCalls, 1);
      assert.equal(answered.filter(message => message.role === 'system').length, 1);
    });
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('PDF numbered sections preserve their title and do not treat inline references as headings', async () => {
  const {chunkDocument} = await import('../src/rag.js');
  const chunks = chunkDocument({name: 'manual.pdf', content:
    '13.9 Модели учета ...............474\n' +
    'См.\nраздел Использование профилей настроек. Если профиль настроек не\n' +
    '13.9 МОДЕЛИ УЧЕТА\n13.9.1 Модели учета\nНазначение\n' +
    'Модели учета объединяют однородные объекты хранения.\n' +
    '13.9.2 Сроки хранения\nПравила определения сроков хранения.'}, 'structure');
  const definition = chunks.find(chunk => chunk.section === '13.9.1 Модели учета');
  assert.match(definition.content, /^13\.9\.1 Модели учета\nНазначение/);
  assert.match(definition.content, /объединяют однородные/);
  assert.ok(!chunks.some(chunk => chunk.section.startsWith('раздел ')));
  assert.ok(!chunks.some(chunk => chunk.section.includes('......')));
});

test('Nomic uses different document and query prefixes and preserves legacy input', async () => {
  const {createOllamaEmbedder} = await import('../src/rag.js');
  const inputs = [];
  const embed = createOllamaEmbedder({baseUrl: 'http://ollama.test', fetchImpl: async (_url, options) => {
    inputs.push(JSON.parse(options.body).input);
    return {ok: true, json: async () => ({embeddings: [[1, 0]]})};
  }});
  await embed(['Document']);
  await embed(['Question'], {task: 'query'});
  await embed(['Old question'], {task: 'query', profile: null});
  assert.deepEqual(inputs, [['search_document: Document'], ['search_query: Question'], ['Old question']]);
  assert.equal(embed.profile.format, 'nomic-task-v1');
});

test('search respects each index embedding profile and rejects a model change of the same dimensionality', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-profile-'));
  const calls = [];
  const embed = async (texts, options) => {
    calls.push(options); return texts.map(() => [1, 0]);
  };
  embed.profile = {model: 'nomic-embed-text', format: 'nomic-task-v1'};
  const store = new RagStore({path: join(directory, 'rag.sqlite'), embed});
  try {
    const rag = store.create('Profile', [{name: 'manual.txt', content: 'A fact'}]);
    store.startIndex(rag.id, 'fixed');
    while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    assert.deepEqual(store.get(rag.id).embeddingProfile, embed.profile);
    assert.equal(calls[0].task, 'document');
    await store.search(rag.id, 'Question');
    assert.equal(calls.at(-1).task, 'query');
    assert.deepEqual(calls.at(-1).profile, embed.profile);
    store.db.prepare('UPDATE rags SET embedding_profile = NULL WHERE id = ?').run(rag.id);
    await store.search(rag.id, 'Old question');
    assert.equal(calls.at(-1).profile, null);
    store.db.prepare('UPDATE rags SET embedding_profile = ? WHERE id = ?')
      .run(JSON.stringify({model: 'other-model', format: 'plain-v1'}), rag.id);
    await assert.rejects(() => store.search(rag.id, 'Question'), /Модель эмбеддингов изменилась/);
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('RAG instructions retain scope across multiple bases and omit empty prompts', () => {
  const messages = ragPromptMessages({searches: [
    {ragId: 'a', ragName: 'First'}, {ragId: 'b', ragName: 'Second'},
    {ragId: 'a', ragName: 'First'}, {ragId: 'c', ragName: 'Empty'},
  ], settingsByRag: {a: {prompt: 'Use tables'}, b: {prompt: 'Cite sources'}, c: {prompt: '   '}}});
  assert.equal(messages.length, 1);
  assert.equal(messages[0].role, 'system');
  assert.match(messages[0].content, /First.*\nUse tables/);
  assert.match(messages[0].content, /Second.*\nCite sources/);
  assert.equal(messages[0].content.split('Use tables').length, 2);
  assert.doesNotMatch(messages[0].content, /Empty/);
  assert.deepEqual(ragPromptMessages({searches: [], settingsByRag: {}}), []);
});

test('Ollama receives actual connections and corrections for invented RAG identifiers', async () => {
  const {store, rag, directory} = await fixture();
  let calls = 0;
  const ollama = {async completeWithTools(messages, {tools}) {
    assert.match(messages[0].content, /Начальный поиск уже выполнен/);
    assert.ok(messages[0].content.includes(rag.id));
    for (const tool of tools) assert.deepEqual(tool.function.parameters.properties.rag_id.enum, [rag.id]);
    if (calls++ === 0) return {message: {role: 'assistant', content: '', tool_calls: [
      {function: {name: 'rag_search', arguments: {rag_id: 'Knowledge', query: 'Alpha'}}},
      {function: {name: 'rag_get_neighbor_chunk', arguments: {rag_id: 'Knowledge', chunk_id: 'invented', direction: 'after'}}},
    ]}};
    const outputs = messages.filter(message => message.role === 'tool').map(message => JSON.parse(message.content));
    assert.deepEqual(outputs[0].connected_rags, [rag.id]);
    assert.deepEqual(outputs[1].connected_rags, [rag.id]);
    assert.ok(outputs[1].allowed_chunks[rag.id].length > 0);
    return {message: {role: 'assistant', content: 'Alpha price: 100'}};
  }};
  try {
    store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false});
    await withServer(store, {ollama}, async base => {
      const res = await fetch(`${base}/api/chat`, jsonRequest('POST', {
        provider: 'ollama', model: 'local-gigachat', systemPrompt: 'Answer', ragIds: [rag.id],
        messages: [{role: 'user', content: 'Alpha'}],
      }));
      const events = (await res.text()).trim().split('\n').map(JSON.parse);
      assert.ok(events.some(event => event.text === 'Alpha price: 100'));
      assert.ok(!events.some(event => event.type === 'error'));
    });
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('chat without RAG tells the model that document search is unavailable', async () => {
  const ollama = {async *generateStream(messages) {
    assert.match(messages[0].content, /К этому запросу RAG не подключён/);
    yield 'Answer';
  }};
  await withServer(undefined, {ollama}, async base => {
    const res = await fetch(`${base}/api/chat`, jsonRequest('POST', {
      provider: 'ollama', model: 'local-gigachat', systemPrompt: 'Answer', messages: [{role: 'user', content: 'Question'}],
    }));
    assert.match(await res.text(), /Answer/);
  });
});
