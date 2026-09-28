import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

import {createApp} from '../src/app.js';
import {chunkDocument, parseUploadedDocuments, RagStore, validateDocuments} from '../src/rag.js';

function simplePdf(text) {
  const stream = `BT /F1 18 Tf 50 150 Td (${text}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, i) => {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${i + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n`;
  pdf += offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(pdf);
}

test('fixed and structure chunking preserve section metadata', () => {
  const document = {name: 'guide.md', content: '# Introduction\nAlpha\n## Details\nBeta'};
  const fixed = chunkDocument(document, 'fixed');
  assert.equal(fixed.length, 1);
  assert.equal(fixed[0].section, 'guide.md');
  const structured = chunkDocument(document, 'structure');
  assert.deepEqual(structured.map(chunk => [chunk.section, chunk.content]),
    [['Introduction', 'Alpha'], ['Details', 'Beta']]);
  assert.equal(validateDocuments([{name: 'guide.md', content: document.content}]), null);
  assert.match(validateDocuments([{name: '../bad.md', content: 'x'}]), /Выберите/);
  assert.equal(validateDocuments(Array.from({length: 21}, (_, i) => ({
    name: `${i}.txt`, content: 'text',
  }))), null);
  assert.equal(validateDocuments([{name: 'large.txt', content: 'x'.repeat(2_000_001)}]), null);
});

test('PDF upload extracts text and rejects an image-only or invalid PDF', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-pdf-test-'));
  try {
    const path = join(directory, 'document.pdf');
    writeFileSync(path, simplePdf('Hello PDF'));
    const documents = await parseUploadedDocuments([{originalname: 'document.pdf', path}]);
    assert.equal(documents.length, 1);
    assert.match(documents[0].content, /Hello PDF/);
    writeFileSync(path, 'not a PDF');
    await assert.rejects(() => parseUploadedDocuments([{originalname: 'document.pdf', path}]));
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});

test('RAG API accepts multipart PDF and more than 20 documents', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-api-test-'));
  const store = new RagStore({path: join(directory, 'rag.sqlite'),
    embed: async texts => texts.map(() => [1])});
  const server = createApp({ragStore: store}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const form = new FormData();
    form.set('name', 'Many files');
    form.append('documents', new Blob([simplePdf('Hello PDF')], {type: 'application/pdf'}), 'paper.pdf');
    for (let i = 0; i < 21; i++) {
      form.append('documents', new Blob([`Text ${i}`], {type: 'text/plain'}), `${i}.txt`);
    }
    form.append('documents', new Blob(['Текст'], {type: 'text/plain'}), 'документ.txt');
    const response = await fetch(`${base}/api/rags`, {method: 'POST', body: form});
    assert.equal(response.status, 201);
    const rag = await response.json();
    assert.equal(rag.documents.length, 23);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM rag_documents').get().count, 23);
    assert.ok(rag.documents.some(document => document.name === 'документ.txt'));
    assert.match(store.db.prepare("SELECT content FROM rag_documents WHERE name = 'paper.pdf'").get().content,
      /Hello PDF/);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});

test('RAG API accepts a document larger than 20 MB', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-large-test-'));
  const store = new RagStore({path: join(directory, 'rag.sqlite'),
    embed: async texts => texts.map(() => [1])});
  const server = createApp({ragStore: store}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const form = new FormData();
    form.set('name', 'Large file');
    const content = 'x'.repeat(21 * 1024 * 1024);
    form.append('documents', new Blob([content]), 'large.txt');
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/rags`,
      {method: 'POST', body: form});
    assert.equal(response.status, 201);
    assert.equal(store.db.prepare('SELECT length(content) AS size FROM rag_documents').get().size,
      content.length);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});

test('indexing persists vectors and metadata, and failure preserves the previous index', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-test-'));
  let fail = false;
  const store = new RagStore({path: join(directory, 'rag.sqlite'), embed: async texts => {
    if (fail) throw new Error('embedding unavailable');
    return texts.map(text => [text.length, 1]);
  }});
  try {
    const rag = store.create('Guide', [{name: 'guide.md', content: '# Intro\nAlpha\n# Next\nBeta'}]);
    assert.equal(rag.documents.length, 1);
    assert.equal(store.startIndex(rag.id, 'structure'), true);
    while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    assert.equal(store.get(rag.id).chunkCount, 2);
    const rows = store.db.prepare('SELECT source, title, section, chunk_id, embedding FROM rag_chunks ORDER BY chunk_id').all();
    assert.deepEqual(rows.map(row => row.section), ['Intro', 'Next']);
    assert.equal(rows[0].source, 'guide.md');
    assert.equal(rows[0].title, 'guide.md');
    assert.match(rows[0].chunk_id, /:1$/);
    assert.deepEqual(JSON.parse(rows[0].embedding), [5, 1]);

    fail = true;
    store.startIndex(rag.id, 'fixed');
    while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    assert.equal(store.get(rag.id).status, 'error');
    assert.match(store.get(rag.id).error, /embedding unavailable/);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM rag_chunks').get().count, 2);
  } finally {
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});

test('selected RAG retrieves relevant chunks and supplies them to chat', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'rag-chat-test-'));
  const store = new RagStore({path: join(directory, 'rag.sqlite'), embed: async texts =>
    texts.map(text => /alpha/i.test(text) ? [1, 0] : [0, 1])});
  const rag = store.create('Knowledge', [
    {name: 'alpha.txt', content: 'Alpha facts'},
    {name: 'beta.txt', content: 'Beta facts'},
  ]);
  const secondRag = store.create('More knowledge', [
    {name: 'gamma.txt', content: 'Gamma facts'},
  ]);
  let received;
  const deepseek = {async *generateStream(messages) {
    received = messages;
    yield 'Answer';
  }};
  const server = createApp({ragStore: store, deepseek}).listen(0, '127.0.0.1');
  try {
    await new Promise(resolve => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const body = {provider: 'deepseek', model: 'deepseek-v4-flash',
      systemPrompt: 'Answer', ragIds: [rag.id, secondRag.id],
      messages: [{role: 'user', content: 'Tell me about Alpha'}]};
    const unindexed = await fetch(`${base}/api/chat`, {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    assert.equal(unindexed.status, 409);
    store.startIndex(rag.id, 'fixed');
    while (store.get(rag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    store.startIndex(secondRag.id, 'fixed');
    while (store.get(secondRag.id).status === 'indexing') await new Promise(resolve => setTimeout(resolve, 1));
    const renamed = await fetch(`${base}/api/rags/${rag.id}`, {method: 'PATCH',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({name: 'Updated knowledge'})});
    assert.equal(renamed.status, 200);
    assert.equal((await renamed.json()).name, 'Updated knowledge');
    const pageResponse = await fetch(`${base}/api/rags/${rag.id}/chunks?offset=0&limit=1`);
    assert.equal(pageResponse.status, 200);
    const page = await pageResponse.json();
    assert.equal(page.total, 2);
    assert.equal(page.chunks.length, 1);
    assert.equal(page.chunks[0].source, 'alpha.txt');
    assert.equal(page.chunks[0].title, 'alpha.txt');
    assert.equal(page.chunks[0].section, 'alpha.txt');
    assert.match(page.chunks[0].chunkId, /:1$/);
    assert.deepEqual(page.chunks[0].embedding, [1, 0]);
    assert.equal((await fetch(`${base}/api/rags/${rag.id}/chunks?limit=0`)).status, 400);
    const found = await store.searchMany([rag.id, secondRag.id], 'Alpha question');
    assert.equal(found.chunks[0].source, 'alpha.txt');
    assert.equal(found.chunks.length, 3);
    const response = await fetch(`${base}/api/chat`, {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Answer/);
    assert.deepEqual(received.map(message => message.role), ['system', 'assistant', 'user']);
    assert.match(received[1].content, /Alpha facts/);
    assert.match(received[1].content, /alpha\.txt/);
    assert.match(received[1].content, /Gamma facts/);
    assert.match(received[1].content, /More knowledge/);
    assert.doesNotMatch(received[0].content, /Alpha facts/);
    const removed = await fetch(`${base}/api/rags/${rag.id}`, {method: 'DELETE'});
    assert.equal(removed.status, 200);
    assert.deepEqual(await removed.json(), {deleted: true});
    assert.equal(store.get(rag.id), null);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM rag_documents WHERE rag_id = ?')
      .get(rag.id).count, 0);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS count FROM rag_chunks WHERE rag_id = ?')
      .get(rag.id).count, 0);
    assert.ok(store.get(secondRag.id));
    assert.equal((await fetch(`${base}/api/rags/${rag.id}`, {method: 'DELETE'})).status, 404);
  } finally {
    await new Promise(resolve => server.close(resolve));
    store.close();
    rmSync(directory, {recursive: true, force: true});
  }
});
