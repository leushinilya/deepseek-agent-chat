import 'dotenv/config';

import {createApp} from './app.js';
import {createDeepSeekClient} from './deepseek.js';

const apiKey = process.env.DEEPSEEK_API_KEY;
if (!apiKey) {
  console.error('DEEPSEEK_API_KEY is not configured. Add it to backend/.env.');
  process.exit(1);
}

const port = Number(process.env.PORT || 3000);
const ai = createDeepSeekClient({
  apiKey,
  model: process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash',
  apiUrl: process.env.DEEPSEEK_API_URL || 'https://api.deepseek.com/chat/completions',
});

createApp({ai, frontendOrigin: process.env.FRONTEND_ORIGIN}).listen(port, () => {
  console.log(`DeepSeek proxy is listening on http://localhost:${port}`);
});
