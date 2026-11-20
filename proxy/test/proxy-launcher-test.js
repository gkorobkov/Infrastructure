import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { copyFileSync, mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

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
test('Windows CMD starts the helper independently and forwards arguments from paths with spaces', {skip: process.platform !== 'win32'}, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'proxy launcher '));
  try {
    copyFileSync(join(root, 'proxy-start-win.cmd'), join(dir, 'proxy-start-win.cmd'));
    writeFileSync(join(dir, 'proxy-start-win.ps1'), [
      'Start-Sleep -Seconds 2',
      '$args | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $PSScriptRoot "result.json")',
      '[Environment]::Exit(0)'
    ].join('\r\n'));
    const result = spawnSync(process.env.ComSpec || 'cmd.exe', ['/d', '/c', 'proxy-start-win.cmd --allow-origin https://client.example'], {cwd:dir, stdio:'ignore', timeout:10000});
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const output = join(dir, 'result.json');
    assert.equal(existsSync(output), false, 'CMD must return before the helper finishes');
    for (let attempt = 0; attempt < 100 && !existsSync(output); attempt++) await delay(100);
    assert.deepEqual(JSON.parse(readFileSync(output, 'utf8').replace(/^\uFEFF/, '')), ['--allow-origin', 'https://client.example']);
  } finally {
    assert.equal(dirname(dir), tmpdir());
    try { rmSync(dir, {recursive:true, force:true, maxRetries:10, retryDelay:100}); }
    catch (error) { if (error.code !== 'EBUSY') throw error; } // Windows console hosts may briefly retain their working directory.
  }
});
