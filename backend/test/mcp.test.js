import assert from 'node:assert/strict';
import test from 'node:test';
import {resolve} from 'node:path';

import {browseMcpDirectories, openFilesystemServer} from '../src/mcp.js';

test('filesystem MCP starts with allowed roots and exposes editing tools', async () => {
  const original = process.env.MCP_ALLOWED_ROOTS;
  process.env.MCP_ALLOWED_ROOTS = process.cwd();
  try {
    const server = await openFilesystemServer([process.cwd()]);
    try {
      const {tools} = await server.listTools();
      assert.ok(tools.some(tool => tool.name === 'edit_file'));
      const result = await server.callTool('list_allowed_directories', {});
      assert.match(JSON.stringify(result), /backend/);
    } finally { server.close(); }
    await assert.rejects(openFilesystemServer(['/']), /Недоступный каталог MCP/);
  } finally {
    if (original === undefined) delete process.env.MCP_ALLOWED_ROOTS;
    else process.env.MCP_ALLOWED_ROOTS = original;
  }
});

test('directory browser lists only allowed folders', async () => {
  const original = process.env.MCP_ALLOWED_ROOTS;
  process.env.MCP_ALLOWED_ROOTS = process.cwd();
  try {
    const roots = await browseMcpDirectories();
    assert.deepEqual(roots.directories.map(item => item.path), [process.cwd()]);
    const listing = await browseMcpDirectories(process.cwd());
    assert.ok(listing.directories.some(item => item.name === 'src'));
    assert.ok(listing.directories.every(item => item.path.startsWith(process.cwd())));
    await assert.rejects(browseMcpDirectories('/'), /Каталог недоступен/);
    await assert.rejects(browseMcpDirectories('../'), /абсолютный путь/);
    await assert.rejects(browseMcpDirectories(resolve('missing-mcp-directory-test')),
      /Каталог не найден/);
  } finally {
    if (original === undefined) delete process.env.MCP_ALLOWED_ROOTS;
    else process.env.MCP_ALLOWED_ROOTS = original;
  }
});
