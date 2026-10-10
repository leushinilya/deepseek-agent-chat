import 'dotenv/config';

import {createApp} from './app.js';
import {createDeepSeekClient} from './deepseek.js';
import {createOllamaClient} from './ollama.js';
import {createOllamaEmbedder, RagStore} from './rag.js';

const apiKey = process.env.DEEPSEEK_API_KEY;
if (!apiKey) {
  console.warn('DEEPSEEK_API_KEY is not configured. DeepSeek models will be unavailable.');
}

const port = Number(process.env.PORT || 3000);
const deepseek = createDeepSeekClient({
  apiKey,
  apiUrl: process.env.DEEPSEEK_API_URL || 'https://api.deepseek.com/chat/completions',
});
const ollamaContextSize = Number(process.env.OLLAMA_NUM_CTX || 32768);
if (!Number.isInteger(ollamaContextSize) || ollamaContextSize <= 0) {
  throw new Error('OLLAMA_NUM_CTX должен быть положительным целым числом.');
}
const ollama = createOllamaClient({
  contextSize: ollamaContextSize,
  models: {
    'local-gigachat': process.env.LOCAL_MODEL || 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
    'local-gigachat-q8': process.env.LOCAL_MODEL_Q8 || 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q8_0',
  },
  apiUrl: process.env.OLLAMA_API_URL || `${process.env.OLLAMA_BASE_URL || 'http://localhost:11434'}/api/chat`,
  model:
    process.env.LOCAL_MODEL ||
    'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
});

const ollamaBaseUrl = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
const ragStore = new RagStore({
  path: process.env.RAG_DB_PATH || 'data/rag.sqlite',
  embed: createOllamaEmbedder({
    baseUrl: ollamaBaseUrl,
    model: process.env.RAG_EMBED_MODEL || 'nomic-embed-text',
  }),
});

createApp({deepseek, ollama, frontendOrigin: process.env.FRONTEND_ORIGIN, ragStore}).listen(port, () => {
  console.log(`AI comparison proxy is listening on http://localhost:${port}`);
});
