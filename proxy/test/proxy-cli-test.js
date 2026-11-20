import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';

for (const explicit of [false, true]) {
  test(`startup lists additional origins only when configured (${explicit})`, {timeout:15000}, async () => {
    const dir = mkdtempSync(join(tmpdir(), 'proxy-cli-'));
    const child = spawn(process.execPath, [fileURLToPath(new URL('../src/proxy-cli.js', import.meta.url)),
      ...(explicit ? ['--allow-origin', 'https://client.example'] : [])], {
      cwd:dir, env:{...process.env, PROXY_ALLOWED_ORIGINS:'', PROXY_LOG_PATH:join(dir, 'proxy.log')},
      stdio:['ignore', 'pipe', 'pipe'],
    });
    const closed = once(child, 'close');
    let output = '';
    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(Error('Startup timed out: ' + output)), 10000);
        child.stdout.on('data', data => {
          output += data;
          if (output.includes('Press Ctrl+C to stop.')) { clearTimeout(timer); resolve(); }
        });
        child.once('error', error => { clearTimeout(timer); reject(error); });
        child.once('exit', () => { clearTimeout(timer); reject(Error('Exited before startup: ' + output)); });
      });
      assert.match(output, /Loopback browser origins:.*any port/);
      assert.doesNotMatch(output, /localhost:(3000|5173)|127\.0\.0\.1:(3000|5173)/);
      if (explicit) assert.match(output, /Additional exact browser origins:\r?\n  https:\/\/client\.example/);
      else assert.doesNotMatch(output, /Additional exact browser origins/);
    } finally {
      child.kill();
      await closed;
      rmSync(dir, {recursive:true, force:true});
    }
  });
}
