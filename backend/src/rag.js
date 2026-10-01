import {randomUUID} from 'node:crypto';
import {mkdirSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import {dirname} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {PDFParse} from 'pdf-parse';
import {sectionHeading} from './rag_sections.js';

const documentNamePattern = /^[^/\\\u0000-\u001f]{1,200}\.(txt|md|markdown|csv|json|pdf)$/i;

export function validateDocuments(documents) {
  if (!Array.isArray(documents) || !documents.length ||
      documents.some(file => !file || typeof file.name !== 'string' ||
        !documentNamePattern.test(file.name) ||
        typeof file.content !== 'string' || !file.content.trim())) {
    return 'Выберите непустые файлы TXT, MD, CSV, JSON или PDF.';
  }
  return null;
}

export async function parseUploadedDocuments(files) {
  if (!Array.isArray(files) || files.length === 0) {
    throw new Error('Выберите хотя бы один документ.');
  }
  const documents = [];
  for (const file of files) {
    // Multipart filenames arrive as Latin-1 byte strings in Busboy/Multer.
    const decodedName = Buffer.from(file.originalname, 'latin1').toString('utf8');
    const name = decodedName.includes('\uFFFD') ? file.originalname : decodedName;
    if (!documentNamePattern.test(name)) {
      throw new Error(`Неподдерживаемый файл: ${name}.`);
    }
    let content;
    if (/\.pdf$/i.test(name)) {
      const parser = new PDFParse({data: await readFile(file.path)});
      try {
        content = (await parser.getText()).text;
      } catch {
        throw new Error(`Не удалось прочитать PDF: ${name}.`);
      } finally {
        await parser.destroy();
      }
    } else {
      content = await readFile(file.path, 'utf8');
    }
    if (!content?.trim()) {
      throw new Error(`В файле ${name} нет извлекаемого текста.`);
    }
    documents.push({name, content});
  }
  return documents;
}

function splitFixed(text, size = 1000, overlap = 150) {
  const chunks = [];
  const source = text.trim();
  for (let start = 0; start < source.length; start += size - overlap) {
    const end = Math.min(start + size, source.length);
    const part = source.slice(start, end).trim();
    if (part) chunks.push({content: part, section: null});
    if (end === source.length) break;
  }
  return chunks;
}

export function chunkDocument(document, strategy) {
  if (strategy === 'fixed') return splitFixed(document.content)
    .map(chunk => ({...chunk, section: document.name, sectionIndex: 0}));
  if (strategy !== 'structure') throw new Error('Неизвестная стратегия разбиения.');
  const result = [];
  const sections = [];
  let heading = document.name;
  let lines = [];
  const flush = () => {
    const content = lines.join('\n').trim();
    if (content) sections.push({section: heading, content});
    lines = [];
  };
  for (const line of document.content.split(/\r?\n/)) {
    const matched = sectionHeading(line);
    if (matched) {
      flush();
      heading = matched.title;
      if (matched.includeInContent) lines.push(heading);
    } else {
      lines.push(line);
    }
  }
  flush();
  for (const [sectionIndex, section] of sections.entries()) {
    for (const part of splitFixed(section.content)) {
      result.push({...part, section: section.section, sectionIndex});
    }
  }
  return result;
}

export function createOllamaEmbedder({baseUrl, model = 'nomic-embed-text', fetchImpl = fetch}) {
  const profile = Object.freeze({model,
    format: /^nomic-embed-text(?::|$)/.test(model) ? 'nomic-task-v1' : 'plain-v1'});
  const embed = async (texts, {task = 'document', profile: requestedProfile = profile} = {}) => {
    const input = requestedProfile?.format === 'nomic-task-v1'
      ? texts.map(text => `${task === 'query' ? 'search_query' : 'search_document'}: ${text}`)
      : texts;
    let response;
    try {
      response = await fetchImpl(`${baseUrl}/api/embed`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({model, input}),
        signal: AbortSignal.timeout(120000),
      });
    } catch {
      throw new Error('Не удалось подключиться к Ollama для генерации эмбеддингов.');
    }
    if (!response.ok) throw new Error(`Ollama не создала эмбеддинги (HTTP ${response.status}). Проверьте модель ${model}.`);
    const data = await response.json();
    if (!Array.isArray(data.embeddings) || data.embeddings.length !== texts.length ||
        data.embeddings.some(vector => !Array.isArray(vector) || !vector.length ||
          vector.some(value => typeof value !== 'number' || !Number.isFinite(value)))) {
      throw new Error('Ollama вернула некорректные эмбеддинги.');
    }
    return data.embeddings;
  };
  embed.profile = profile;
  return embed;
}

export const defaultRetrievalSettings = Object.freeze({
  prompt: '', filterEnabled: true, rewriteEnabled: true, similarityThreshold: 0.3,
  candidateK: 20, resultK: 5, neighborRadius: 1,
  maxExpansionCalls: 3, maxSearchCalls: 3, maxContextChars: 20000,
});

export function validateRetrievalSettings(value) {
  if (value?.prompt !== undefined && (typeof value.prompt !== 'string' || value.prompt.length > 10000)) {
    return 'Промт RAG должен быть текстом длиной до 10000 символов.';
  }
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !Object.hasOwn(defaultRetrievalSettings, key)) ||
      typeof value.filterEnabled !== 'boolean' || typeof value.rewriteEnabled !== 'boolean' ||
      !Number.isFinite(value.similarityThreshold) || value.similarityThreshold < -1 || value.similarityThreshold > 1 ||
      !Number.isInteger(value.candidateK) || value.candidateK < 1 || value.candidateK > 100 ||
      !Number.isInteger(value.resultK) || value.resultK < 1 || value.resultK > value.candidateK ||
      !Number.isInteger(value.neighborRadius) || value.neighborRadius < 0 || value.neighborRadius > 2 ||
      !Number.isInteger(value.maxExpansionCalls) || value.maxExpansionCalls < 0 || value.maxExpansionCalls > 5 ||
      !Number.isInteger(value.maxSearchCalls) || value.maxSearchCalls < 0 || value.maxSearchCalls > 5 ||
      !Number.isInteger(value.maxContextChars) || value.maxContextChars < 1000 || value.maxContextChars > 50000) {
    return 'Настройки поиска некорректны: top-K от 1 до 100, similarity от −1 до 1, соседи от 0 до 2, догрузки и повторные поиски от 0 до 5, контекст от 1000 до 50000 символов.';
  }
  return null;
}

export class RagStore {
  constructor({path, embed}) {
    mkdirSync(dirname(path), {recursive: true});
    this.db = new DatabaseSync(path);
    this.embed = embed;
    this.running = new Set();
    this.db.exec(`
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS rags (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ready',
        strategy TEXT, error TEXT, chunk_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS rag_documents (
        id TEXT PRIMARY KEY, rag_id TEXT NOT NULL REFERENCES rags(id) ON DELETE CASCADE,
        name TEXT NOT NULL, content TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS rag_chunks (
        chunk_id TEXT PRIMARY KEY, rag_id TEXT NOT NULL REFERENCES rags(id) ON DELETE CASCADE,
        document_id TEXT NOT NULL REFERENCES rag_documents(id) ON DELETE CASCADE,
        source TEXT NOT NULL, title TEXT NOT NULL, section TEXT,
        content TEXT NOT NULL, embedding TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS rag_pending_chunks (
        run_id TEXT NOT NULL, chunk_id TEXT NOT NULL, rag_id TEXT NOT NULL,
        document_id TEXT NOT NULL, source TEXT NOT NULL, title TEXT NOT NULL,
        section TEXT, content TEXT NOT NULL, embedding TEXT NOT NULL,
        PRIMARY KEY (run_id, chunk_id)
      );
      CREATE INDEX IF NOT EXISTS rag_chunks_rag_id ON rag_chunks(rag_id);
      DELETE FROM rag_pending_chunks;
      UPDATE rags SET status = 'error', error = 'Индексация прервана перезапуском сервера.'
      WHERE status = 'indexing';
    `);
    const columns = this.db.prepare('PRAGMA table_info(rags)').all();
    for (const name of ['retrieval_settings', 'embedding_profile']) {
      if (!columns.some(column => column.name === name)) {
        this.db.exec(`ALTER TABLE rags ADD COLUMN ${name} TEXT`);
      }
    }
    for (const table of ['rag_chunks', 'rag_pending_chunks']) {
      const columns = this.db.prepare(`PRAGMA table_info(${table})`).all();
      for (const name of ['previous_chunk_id', 'next_chunk_id']) {
        if (!columns.some(column => column.name === name)) {
          this.db.exec(`ALTER TABLE ${table} ADD COLUMN ${name} TEXT`);
        }
      }
    }
  }

  list() {
    return this.db.prepare(`SELECT r.id, r.name, r.status, r.strategy, r.error,
      r.chunk_count AS chunkCount, r.created_at AS createdAt, r.retrieval_settings, r.embedding_profile,
      COUNT(d.id) AS documentCount FROM rags r
      LEFT JOIN rag_documents d ON d.rag_id = r.id
      GROUP BY r.id ORDER BY r.created_at DESC`).all().map(row => this._settings(row));
  }

  get(id) {
    const rag = this.db.prepare(`SELECT id, name, status, strategy, error,
      chunk_count AS chunkCount, created_at AS createdAt, retrieval_settings, embedding_profile FROM rags WHERE id = ?`).get(id);
    if (!rag) return null;
    return {...this._settings(rag), documents: this.db.prepare(
      'SELECT id, name FROM rag_documents WHERE rag_id = ? ORDER BY rowid').all(id)};
  }

  _settings({retrieval_settings, embedding_profile, ...rag}) {
    return {...rag, embeddingProfile: embedding_profile ? JSON.parse(embedding_profile) : null,
      retrievalSettings: {...defaultRetrievalSettings,
      ...(retrieval_settings ? JSON.parse(retrieval_settings) : {})}};
  }

  updateSettings(id, settings) {
    const error = validateRetrievalSettings(settings);
    if (error) throw new Error(error);
    const result = this.db.prepare('UPDATE rags SET retrieval_settings = ? WHERE id = ?')
      .run(JSON.stringify({...defaultRetrievalSettings, ...settings}), id);
    return result.changes ? this.get(id) : null;
  }

  async retrieve(ids, originalQuery, {rewrite, baseline = false,
    settingsOverrides = new Map()} = {}) {
    const rags = ids.map(id => this.get(id));
    if (rags.some(rag => !rag)) throw new Error('Один из выбранных RAG не найден.');
    if (rags.some(rag => rag.status !== 'indexed')) throw new Error('Один из выбранных RAG ещё не проиндексирован.');
    for (const rag of rags) {
      rag.retrievalSettings = settingsOverrides.get(rag.id) ?? rag.retrievalSettings;
    }
    const rewrittenQuery = !baseline && rags.some(rag => rag.retrievalSettings.rewriteEnabled)
      ? await rewrite(originalQuery) : null;
    const chunks = [];
    const searches = [];
    for (const rag of rags) {
      const settings = rag.retrievalSettings;
      const query = !baseline && settings.rewriteEnabled ? rewrittenQuery : originalQuery;
      const found = await this.searchMany([rag.id], query, baseline ? 5 : settings.candidateK);
      const relevant = !baseline && settings.filterEnabled
        ? found.chunks.filter(chunk => chunk.score >= settings.similarityThreshold) : found.chunks;
      const selected = relevant.slice(0, baseline ? 5 : settings.resultK);
      const delivered = new Set();
      let usedChars = 0;
      const add = chunk => {
        if (!chunk || delivered.has(chunk.chunkId) ||
            usedChars + chunk.content.length > settings.maxContextChars) return;
        delivered.add(chunk.chunkId);
        usedChars += chunk.content.length;
        chunks.push(chunk);
      };
      for (const chunk of selected) {
        add(chunk);
        if (!baseline && settings.neighborRadius) {
          for (const neighbor of this.linkedChunks(rag.id, chunk.chunkId, settings.neighborRadius)) {
            add(neighbor);
          }
        }
      }
      searches.push({ragId: rag.id, ragName: rag.name, query,
        candidateCount: found.chunks.length, relevantCount: relevant.length,
        selectedCount: selected.length, deliveredCount: delivered.size,
        candidates: found.chunks.map(chunk => ({...chunk,
          selected: selected.some(item => item.chunkId === chunk.chunkId)}))});
    }
    return {names: rags.map(rag => rag.name), originalQuery, rewrittenQuery, chunks, searches,
      settingsByRag: Object.fromEntries(rags.map(rag => [rag.id, rag.retrievalSettings]))};
  }

  rename(id, name) {
    const result = this.db.prepare('UPDATE rags SET name = ? WHERE id = ?').run(name, id);
    return result.changes ? this.get(id) : null;
  }

  remove(id) {
    if (this.running.has(id)) throw new Error('Дождитесь окончания индексации.');
    return this.db.prepare('DELETE FROM rags WHERE id = ?').run(id).changes > 0;
  }

  chunks(id, {offset = 0, limit = 10} = {}) {
    if (!this.db.prepare('SELECT 1 FROM rags WHERE id = ?').get(id)) return null;
    const total = this.db.prepare('SELECT COUNT(*) AS count FROM rag_chunks WHERE rag_id = ?')
      .get(id).count;
    const chunks = this.db.prepare(`SELECT chunk_id AS chunkId, source, title, section,
      content, embedding, previous_chunk_id AS previousChunkId,
      next_chunk_id AS nextChunkId FROM rag_chunks WHERE rag_id = ?
      ORDER BY source, chunk_id LIMIT ? OFFSET ?`).all(id, limit, offset)
      .map(row => ({...row, embedding: JSON.parse(row.embedding)}));
    return {total, offset, limit, chunks};
  }

  linkedChunks(ragId, chunkId, radius = 1, direction = 'both') {
    const row = this.db.prepare(`SELECT chunk_id AS chunkId, rag_id AS ragId,
      previous_chunk_id AS previousChunkId, next_chunk_id AS nextChunkId,
      source, title, section, content FROM rag_chunks WHERE rag_id = ? AND chunk_id = ?`);
    const origin = row.get(ragId, chunkId);
    if (!origin) return [];
    const result = [];
    for (const field of direction === 'both' ? ['previousChunkId', 'nextChunkId'] :
      [direction === 'before' ? 'previousChunkId' : 'nextChunkId']) {
      let current = origin;
      for (let i = 0; i < radius && current[field]; i++) {
        const neighbor = row.get(ragId, current[field]);
        if (!neighbor) break;
        result.push(neighbor);
        current = neighbor;
      }
    }
    return result;
  }

  async search(id, query, limit = 5) {
    const result = await this.searchMany([id], query, limit);
    return {name: result.names[0], chunks: result.chunks};
  }

  async searchMany(ids, query, limit = 5) {
    const rags = ids.map(id => this.get(id));
    if (rags.some(rag => !rag)) throw new Error('Один из выбранных RAG не найден.');
    if (rags.some(rag => rag.status !== 'indexed')) {
      throw new Error('Один из выбранных RAG ещё не проиндексирован.');
    }
    const queryVectors = new Map();
    const best = [];
    const rows = this.db.prepare(`SELECT chunk_id AS chunkId, source, title, section,
      content, embedding, previous_chunk_id AS previousChunkId,
      next_chunk_id AS nextChunkId FROM rag_chunks WHERE rag_id = ?`);
    for (const rag of rags) {
      const profile = rag.embeddingProfile;
      if (profile && this.embed.profile &&
          profile.model.replace(/:latest$/, '') !== this.embed.profile.model.replace(/:latest$/, '')) {
        throw new Error('Модель эмбеддингов изменилась. Переиндексируйте RAG перед поиском.');
      }
      const key = JSON.stringify(profile);
      if (!queryVectors.has(key)) {
        const [vector] = await this.embed([query.slice(0, 4000)], {task: 'query', profile});
        queryVectors.set(key, vector);
      }
      const queryVector = queryVectors.get(key);
      const queryNorm = Math.hypot(...queryVector);
      if (!queryNorm) throw new Error('Не удалось построить вектор запроса.');
      for (const row of rows.iterate(rag.id)) {
        const vector = JSON.parse(row.embedding);
        if (vector.length !== queryVector.length) {
          throw new Error('Размерность эмбеддингов RAG не совпадает с моделью. Переиндексируйте RAG.');
        }
        const norm = Math.hypot(...vector);
        if (!norm) continue;
        let dot = 0;
        for (let i = 0; i < vector.length; i++) dot += vector[i] * queryVector[i];
        const score = dot / (norm * queryNorm);
        if (!Number.isFinite(score)) continue;
        best.push({ragId: rag.id, ragName: rag.name, chunkId: row.chunkId,
          source: row.source, title: row.title, section: row.section,
          content: row.content, score,
          previousChunkId: row.previousChunkId, nextChunkId: row.nextChunkId});
        best.sort((a, b) => b.score - a.score);
        if (best.length > limit) best.pop();
      }
    }
    return {names: rags.map(rag => rag.name), chunks: best};
  }

  create(name, documents) {
    const id = randomUUID();
    this.db.exec('BEGIN');
    try {
      this.db.prepare('INSERT INTO rags (id, name, created_at) VALUES (?, ?, ?)')
        .run(id, name, new Date().toISOString());
      const insert = this.db.prepare('INSERT INTO rag_documents (id, rag_id, name, content) VALUES (?, ?, ?, ?)');
      for (const file of documents) insert.run(randomUUID(), id, file.name, file.content);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return this.get(id);
  }

  addDocuments(id, documents) {
    const rag = this.get(id);
    if (!rag) return null;
    if (this.running.has(id)) throw new Error('Дождитесь окончания индексации.');
    const insert = this.db.prepare('INSERT INTO rag_documents (id, rag_id, name, content) VALUES (?, ?, ?, ?)');
    this.db.exec('BEGIN');
    try {
      for (const file of documents) insert.run(randomUUID(), id, file.name, file.content);
      this.db.prepare("UPDATE rags SET status = 'ready', error = NULL WHERE id = ?").run(id);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return this.get(id);
  }

  startIndex(id, strategy) {
    if (!['fixed', 'structure'].includes(strategy)) throw new Error('Выберите стратегию разбиения.');
    if (!this.get(id)) return false;
    if (this.running.has(id)) throw new Error('Индексация уже выполняется.');
    this.running.add(id);
    this.db.prepare("UPDATE rags SET status = 'indexing', strategy = ?, error = NULL WHERE id = ?")
      .run(strategy, id);
    void this.index(id, strategy);
    return true;
  }

  async index(id, strategy) {
    const runId = randomUUID();
    const embeddingProfile = this.embed.profile ?? null;
    try {
      const documentIds = this.db.prepare('SELECT id FROM rag_documents WHERE rag_id = ?').all(id);
      const insertPending = this.db.prepare(`INSERT INTO rag_pending_chunks
        (run_id, chunk_id, rag_id, document_id, source, title, section, content, embedding,
         previous_chunk_id, next_chunk_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
      let chunkCount = 0;
      for (const {id: documentId} of documentIds) {
        const document = this.db.prepare('SELECT id, name, content FROM rag_documents WHERE id = ?').get(documentId);
        const chunks = chunkDocument(document, strategy);
        const chunkId = index => `${documentId}:${index + 1}`;
        for (let offset = 0; offset < chunks.length; offset += 16) {
          const batch = chunks.slice(offset, offset + 16);
          const vectors = await this.embed(batch.map(chunk => chunk.content),
            {task: 'document', profile: embeddingProfile});
          if (vectors.length !== batch.length) throw new Error('Ollama вернула не все эмбеддинги.');
          batch.forEach((chunk, index) => {
            const position = offset + index;
            insertPending.run(runId,
            chunkId(position), id, documentId,
            document.name, document.name, chunk.section,
            chunk.content, JSON.stringify(vectors[index]),
            position > 0 && chunks[position - 1].sectionIndex === chunk.sectionIndex
              ? chunkId(position - 1) : null,
            position + 1 < chunks.length && chunks[position + 1].sectionIndex === chunk.sectionIndex
              ? chunkId(position + 1) : null);
          });
          chunkCount += batch.length;
        }
      }
      if (!chunkCount) throw new Error('В документах нет текста для индексации.');
      this.db.exec('BEGIN');
      try {
        this.db.prepare('DELETE FROM rag_chunks WHERE rag_id = ?').run(id);
        this.db.prepare(`INSERT INTO rag_chunks
          (chunk_id, rag_id, document_id, source, title, section, content, embedding,
           previous_chunk_id, next_chunk_id)
          SELECT chunk_id, rag_id, document_id, source, title, section, content, embedding,
                 previous_chunk_id, next_chunk_id
          FROM rag_pending_chunks WHERE run_id = ?`).run(runId);
        this.db.prepare('DELETE FROM rag_pending_chunks WHERE run_id = ?').run(runId);
        this.db.prepare("UPDATE rags SET status = 'indexed', error = NULL, chunk_count = ?, embedding_profile = ? WHERE id = ?")
          .run(chunkCount, embeddingProfile ? JSON.stringify(embeddingProfile) : null, id);
        this.db.exec('COMMIT');
      } catch (error) {
        this.db.exec('ROLLBACK');
        throw error;
      }
    } catch (error) {
      this.db.prepare('DELETE FROM rag_pending_chunks WHERE run_id = ?').run(runId);
      this.db.prepare("UPDATE rags SET status = 'error', error = ? WHERE id = ?")
        .run(error.message || 'Ошибка индексации.', id);
    } finally {
      this.running.delete(id);
    }
  }

  close() { this.db.close(); }
}
