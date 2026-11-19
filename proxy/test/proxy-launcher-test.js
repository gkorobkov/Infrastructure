import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
test('Unix bootstrap: offline installation, refusal, checksum and reuse', {skip: process.platform === 'win32'}, () => {
  const result = spawnSync('sh', ['test/proxy-launcher-test.sh'], {cwd:root, encoding:'utf8', timeout:30000});
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
test('Windows launcher reuses installed Node.js and forwards options', {skip: process.platform !== 'win32'}, () => {
  const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'proxy-start-win.ps1', '--help'], {cwd:root, encoding:'utf8', timeout:30000});
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /Universal HTTP Proxy/);
  assert.match(result.stdout, /--allow-origin/);
});
