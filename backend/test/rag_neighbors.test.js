import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

import {createApp} from '../src/app.js';
import {RagStore, defaultRetrievalSettings} from '../src/rag.js';

async function fixture() {
  const directory = mkdtempSync(join(tmpdir(), 'rag-neighbors-'));
  const embed = async texts => texts.map(text => text.includes('TARGET') ? [1, 0] : [0, 1]);
  const store = new RagStore({path: join(directory, 'rag.sqlite'), embed});
  const rag = store.create('Manual', [{name: 'manual.md', content:
    '# Repeated\n' + 'a'.repeat(1400) + 'TARGET' + 'b'.repeat(2200) +
    '\n# Repeated\n' + 'c'.repeat(2200)}]);
  store.startIndex(rag.id, 'structure');
  while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
  assert.equal(store.get(rag.id).status, 'indexed');
  return {directory, store, rag};
}

test('index links only chunks in the same section and retrieval adds immediate neighbors', async () => {
  const {directory, store, rag} = await fixture();
  try {
    const rows = store.db.prepare(`SELECT chunk_id AS id, previous_chunk_id AS previous,
      next_chunk_id AS next FROM rag_chunks WHERE rag_id = ? ORDER BY rowid`).all(rag.id);
    assert.equal(rows[0].previous, null);
    assert.equal(rows[0].next, rows[1].id);
    const boundary = rows.findIndex((row, index) => index > 0 && row.previous === null);
    assert.ok(boundary > 2);
    assert.equal(rows[boundary - 1].next, null);
    assert.equal(rows[boundary].previous, null);

    store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false,
      candidateK: 1, resultK: 1, neighborRadius: 1});
    const context = await store.retrieve([rag.id], 'TARGET');
    assert.equal(context.searches[0].selectedCount, 1);
    assert.equal(context.chunks.length, 3);
    assert.ok(context.chunks.every(chunk => !chunk.content.includes('c'.repeat(30))));
    assert.equal(new Set(context.chunks.map(chunk => chunk.chunkId)).size, 3);

    store.updateSettings(rag.id, {...store.get(rag.id).retrievalSettings,
      maxContextChars: 1000});
    assert.equal((await store.retrieve([rag.id], 'TARGET')).chunks.length, 1);
  } finally { store.close(); rmSync(directory, {recursive: true, force: true}); }
});

test('agent can request one more linked chunk and receives a bounded tool result', async () => {
  const {directory, store, rag} = await fixture();
  const server = createApp({ragStore: store, deepseek: {
    async generate() { return {answer: 'Baseline', metrics: {}}; },
    async completeWithTools(messages, {tools}) {
      if (!tools.some(tool => tool.function.name === 'rag_get_neighbor_chunk')) {
        assert.ok(tools.some(tool => tool.function.name === 'rag_search'));
        return {message: {role: 'assistant', content: 'Baseline'}};
      }
      const toolResults = messages.filter(message => message.role === 'tool');
      if (toolResults.length) {
        assert.match(JSON.parse(toolResults[0].content).error, /уже полученных/);
        const output = JSON.parse(toolResults[1].content);
        assert.match(output.content, /b{100}/);
        assert.equal(output.remaining_calls, 0);
        assert.match(JSON.parse(toolResults[2].content).error, /лимит догрузок/);
        return {message: {role: 'assistant', content: 'Found the continuation'}};
      }
      return {message: {role: 'assistant', content: null, tool_calls: [
        {id: 'invalid', type: 'function', function: {
          name: 'rag_get_neighbor_chunk',
          arguments: JSON.stringify({rag_id: rag.id, chunk_id: 'unknown', direction: 'after'}),
        }},
        {id: 'fetch-1', type: 'function', function: {
          name: 'rag_get_neighbor_chunk',
          arguments: JSON.stringify({rag_id: rag.id, chunk_id: anchor, direction: 'after'}),
        }},
        {id: 'over-limit', type: 'function', function: {
          name: 'rag_get_neighbor_chunk',
          arguments: JSON.stringify({rag_id: rag.id, chunk_id: anchor, direction: 'after'}),
        }},
      ]}};
    },
  }}).listen(0, '127.0.0.1');
  let anchor;
  try {
    store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false,
      candidateK: 1, resultK: 1, neighborRadius: 1, maxExpansionCalls: 1});
    const context = await store.retrieve([rag.id], 'TARGET');
    anchor = context.chunks.find(chunk => chunk.nextChunkId &&
      !context.chunks.some(other => other.chunkId === chunk.nextChunkId))?.chunkId;
    assert.ok(anchor);
    await new Promise(resolve => server.once('listening', resolve));
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({provider: 'deepseek', model: 'deepseek-v4-pro',
        systemPrompt: 'Answer', ragIds: [rag.id],
        messages: [{role: 'user', content: 'TARGET'}]}),
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Found the continuation/);
    const comparison = await fetch(`http://127.0.0.1:${server.address().port}/api/rags/${rag.id}/compare`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({provider: 'deepseek', model: 'deepseek-v4-pro',
        systemPrompt: 'Answer', query: 'TARGET',
        retrievalSettings: store.get(rag.id).retrievalSettings}),
    });
    assert.equal(comparison.status, 200);
    const compared = await comparison.json();
    assert.equal(compared.baseline.answer, 'Baseline');
    assert.equal(compared.improved.answer, 'Found the continuation');
    const defaultComparison = await fetch(`http://127.0.0.1:${server.address().port}/api/rags/${rag.id}/compare`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({provider: 'deepseek', model: 'deepseek-v4-pro',
        systemPrompt: 'Answer', query: 'TARGET'}),
    });
    assert.equal(defaultComparison.status, 200);
    const defaults = (await defaultComparison.json()).improved;
    assert.equal(defaults.answer, 'Baseline');
    assert.equal(defaults.settingsByRag[rag.id].neighborRadius, 0);
    assert.equal(defaults.settingsByRag[rag.id].maxExpansionCalls, 0);
    assert.equal(defaults.settingsByRag[rag.id].maxSearchCalls, 0);
    assert.equal(store.get(rag.id).retrievalSettings.maxSearchCalls, 3);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});

test('agent can search its connected RAG again during a follow-up turn', async () => {
  const {directory, store, rag} = await fixture();
  let completions = 0;
  const deepseek = {async completeWithTools(messages, {tools}) {
    completions++;
    assert.ok(tools.some(tool => tool.function.name === 'rag_search'));
    const results = messages.filter(message => message.role === 'tool');
    if (results.length) {
      assert.match(JSON.parse(results[0].content).error, /подключённый RAG/);
      const found = JSON.parse(results[1].content);
      assert.equal(found.query, 'TARGET');
      assert.ok(found.chunks.some(chunk => chunk.content.includes('TARGET')));
      assert.equal(JSON.parse(results[2].content).query, 'TARGET again');
      assert.equal(JSON.parse(results[2].content).error, undefined);
      assert.deepEqual(JSON.parse(results[2].content).chunks, []);
      return {message: {role: 'assistant', content: 'Answer from the new search'}};
    }
    const calls = [
      {rag_id: 'unconnected', query: 'TARGET'},
      {rag_id: rag.id, query: 'TARGET'},
      {rag_id: rag.id, query: 'TARGET again'},
    ].map((args, index) => ({id: `search-${index}`, type: 'function', function: {
      name: 'rag_search', arguments: JSON.stringify(args),
    }}));
    return {message: {role: 'assistant', content: null, tool_calls: calls}};
  }};
  const server = createApp({ragStore: store, deepseek}).listen(0, '127.0.0.1');
  try {
    store.updateSettings(rag.id, {...defaultRetrievalSettings, rewriteEnabled: false,
      candidateK: 1, resultK: 1, neighborRadius: 0, maxSearchCalls: 0});
    await new Promise(resolve => server.once('listening', resolve));
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({provider: 'deepseek', model: 'deepseek-v4-pro',
        systemPrompt: 'Answer', ragIds: [rag.id], messages: [
          {role: 'user', content: 'Tell me about the manual'},
          {role: 'assistant', content: 'The manual has several sections.'},
          {role: 'user', content: 'What about the target detail?'},
        ]}),
    });
    assert.equal(response.status, 200);
    const events = (await response.text()).trim().split('\n').map(JSON.parse);
    assert.equal(events.filter(event => event.type === 'rag').length, 3);
    const searches = events.filter(event => event.type === 'rag').at(-1).searches;
    assert.equal(searches.length, 3);
    assert.equal(searches[1].deliveredCount, 1);
    assert.equal(searches[2].selectedCount, 1);
    assert.equal(searches[2].deliveredCount, 0);
    assert.ok(events.some(event => event.text === 'Answer from the new search'), JSON.stringify(events));
    assert.equal(completions, 2);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});
