import assert from 'node:assert/strict';
import test from 'node:test';
import {resolve} from 'node:path';

import {browseMcpDirectories, openFilesystemServer} from '../src/mcp.js';

test('filesystem MCP exposes tools for an explicitly selected directory', async () => {
  const server = await openFilesystemServer([process.cwd()]);
  try {
    const {tools} = await server.listTools();
    assert.ok(tools.some(tool => tool.name === 'edit_file'));
    const result = await server.callTool('list_allowed_directories', {});
    assert.match(JSON.stringify(result), /backend/);
  } finally { server.close(); }
});

test('directory browser navigates from filesystem root without MCP_ALLOWED_ROOTS', async () => {
  const roots = await browseMcpDirectories();
  assert.equal(roots.current, '/');
  assert.ok(roots.directories.length > 0);
  const listing = await browseMcpDirectories(process.cwd());
  assert.ok(listing.directories.some(item => item.name === 'src'));
  await assert.rejects(browseMcpDirectories('../'), /абсолютный путь/);
  await assert.rejects(browseMcpDirectories(resolve('missing-mcp-directory-test')),
    /Каталог не найден/);
});
