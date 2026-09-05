import 'dotenv/config';

import {createApp} from './app.js';
import {createDeepSeekClient} from './deepseek.js';
import {createOllamaClient} from './ollama.js';

const apiKey = process.env.DEEPSEEK_API_KEY;
if (!apiKey) {
  console.error('DEEPSEEK_API_KEY is not configured. Add it to backend/.env.');
  process.exit(1);
}

const port = Number(process.env.PORT || 3000);
const deepseek = createDeepSeekClient({
  apiKey,
  apiUrl: process.env.DEEPSEEK_API_URL || 'https://api.deepseek.com/chat/completions',
});
const ollama = createOllamaClient({
  apiUrl: process.env.OLLAMA_API_URL || 'http://localhost:11434/api/chat',
  model:
    process.env.LOCAL_MODEL ||
    'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M',
});

createApp({deepseek, ollama, frontendOrigin: process.env.FRONTEND_ORIGIN}).listen(port, () => {
  console.log(`AI comparison proxy is listening on http://localhost:${port}`);
});
