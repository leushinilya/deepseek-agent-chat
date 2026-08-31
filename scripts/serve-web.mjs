import {createReadStream, existsSync} from 'node:fs';
import {createServer} from 'node:http';
import {extname, resolve} from 'node:path';

const root = resolve('build/web');
const port = Number(process.env.PORT || 8080);
const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

if (!existsSync(root)) {
  throw new Error('Не найдена build/web. Сначала выполните flutter build web.');
}

createServer((request, response) => {
  const requestPath = decodeURIComponent(request.url?.split('?')[0] || '/');
  const relativePath = requestPath === '/' ? 'index.html' : requestPath.replace(/^\/+/, '');
  const filePath = resolve(root, relativePath);

  if (!filePath.startsWith(root) || !existsSync(filePath)) {
    response.writeHead(404);
    response.end('Not found');
    return;
  }

  response.writeHead(200, {
    'Content-Type': contentTypes[extname(filePath)] || 'application/octet-stream',
  });
  createReadStream(filePath).pipe(response);
}).listen(port, () => {
  console.log(`Flutter Web is available at http://localhost:${port}`);
});
