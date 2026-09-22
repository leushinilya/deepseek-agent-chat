import {spawn} from 'node:child_process';
import {access, readdir, realpath, stat} from 'node:fs/promises';
import {delimiter, isAbsolute, relative, resolve, sep} from 'node:path';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';

export async function openFilesystemServer(directories) {
  if (directories.some(path => !isAbsolute(path))) throw new Error('MCP требует абсолютные пути.');
  const roots = await allowedRoots();
  const allowed = [...new Set(await Promise.all(directories.map(path => existingDirectory(path))))];
  for (const directory of allowed) {
    if (!isWithinRoots(directory, roots) || !(await stat(directory)).isDirectory()) {
      throw new Error(`Недоступный каталог MCP: ${directory}`);
    }
    await access(directory);
  }
  const binary = new URL('../node_modules/@modelcontextprotocol/server-filesystem/dist/index.js', import.meta.url);
  const child = spawn(process.execPath, [fileURLToPath(binary), ...allowed],
    {stdio: ['pipe', 'pipe', 'pipe']});
  const pending = new Map();
  let nextId = 1;
  let stderr = '';
  child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-2000); });
  const fail = error => {
    for (const {reject, timer} of pending.values()) { clearTimeout(timer); reject(error); }
    pending.clear();
  };
  child.on('error', fail);
  child.on('exit', code => fail(new Error(`Filesystem MCP завершился (${code}): ${stderr}`)));
  createInterface({input: child.stdout}).on('line', line => {
    let response;
    try { response = JSON.parse(line); } catch { return; }
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id);
    clearTimeout(request.timer);
    if (response.error) request.reject(new Error(response.error.message));
    else request.resolve(response.result);
  });
  function request(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = nextId++;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Filesystem MCP не ответил: ${method}`));
        child.kill();
      }, 30000);
      pending.set(id, {resolve, reject, timer});
      child.stdin.write(`${JSON.stringify({jsonrpc: '2.0', id, method, params})}\n`);
    });
  }
  try {
    await request('initialize', {
      protocolVersion: '2025-03-26', capabilities: {},
      clientInfo: {name: 'deepseek-agent-chat', version: '1.0.0'},
    });
    child.stdin.write(`${JSON.stringify({jsonrpc: '2.0', method: 'notifications/initialized'})}\n`);
    return {
      listTools: () => request('tools/list'),
      callTool: (name, args) => request('tools/call', {name, arguments: args}),
      close: () => { child.kill(); fail(new Error('MCP connection closed')); },
    };
  } catch (error) {
    child.kill();
    throw error;
  }
}

async function allowedRoots() {
  const configured = (process.env.MCP_ALLOWED_ROOTS ?? '').split(delimiter)
    .filter(Boolean).map(path => resolve(path));
  if (!configured.length) throw new Error('MCP_ALLOWED_ROOTS не настроен на backend.');
  return [...new Set(await Promise.all(configured.map(path => realpath(path))))];
}

function isWithinRoots(path, roots) {
  return roots.some(root => {
    const remainder = relative(root, path);
    return remainder === '' ||
      (remainder !== '..' && !remainder.startsWith(`..${sep}`) && !isAbsolute(remainder));
  });
}

export async function browseMcpDirectories(path) {
  const roots = await allowedRoots();
  if (path === undefined) {
    return {current: null, parent: null,
      directories: roots.map(root => ({name: root, path: root}))};
  }
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new Error('Укажите абсолютный путь к каталогу.');
  }
  const current = await existingDirectory(path);
  if (!isWithinRoots(current, roots) || !(await stat(current)).isDirectory()) {
    throw new Error('Каталог недоступен для MCP.');
  }
  const entries = await readdir(current, {withFileTypes: true});
  const directories = [];
  for (const entry of entries) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    try {
      const child = await realpath(resolve(current, entry.name));
      if (isWithinRoots(child, roots) && (await stat(child)).isDirectory()) {
        directories.push({name: entry.name, path: child});
      }
    } catch { /* An inaccessible child does not prevent browsing its parent. */ }
  }
  directories.sort((a, b) => a.name.localeCompare(b.name));
  const parentPath = resolve(current, '..');
  return {current, parent: isWithinRoots(parentPath, roots) ? parentPath : null,
    directories: directories.slice(0, 500)};
}

async function existingDirectory(path) {
  try {
    return await realpath(path);
  } catch (error) {
    if (error?.code === 'ENOENT') {
      throw new Error(`Каталог не найден: ${path}. Проверьте название или выберите папку в интерфейсе.`);
    }
    throw error;
  }
}
