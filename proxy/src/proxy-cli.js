#!/usr/bin/env node
// Generic loopback HTTP proxy. External web origins require explicit approval.
import { createProxyServer, listen, DEFAULT_ORIGINS } from './proxy-server.js';

const VERSION = '1.0.0';
const args = process.argv.slice(2);
const help = `Universal Local HTTP Proxy
Usage: node src/proxy-cli.js [--port 8080] [--allow-origin https://client.example] [--help] [--version]

Options:
  --port PORT         Listening port (default: 8080; next 10 ports as fallback)
  --allow-origin URL  Authorize this exact browser origin; repeatable
  --help              Show help
  --version           Show version

Environment:
  PROXY_ALLOWED_ORIGINS  Additional comma-separated exact HTTP(S) origins

No public websites are authorized by default.
Example: node src/proxy-cli.js --allow-origin https://client.example`;
if (args.includes('--help') || args.includes('-h')) { console.log(help); process.exit(0); }
if (args.includes('--version')) { console.log(VERSION); process.exit(0); }

let port = 8080;
const additional = (process.env.PROXY_ALLOWED_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean);
function parseOrigin(value) {
  let url;
  try { url = new URL(value); } catch { throw Error('Invalid allowed Origin: ' + value); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.pathname !== '/' || url.search || url.hash || url.origin !== value) {
    throw Error('Allowed Origin must be exact scheme://host[:port] without a path: ' + value);
  }
  return url.origin;
}
try {
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--port') {
      if (!args[i + 1]) throw Error('Missing --port value.');
      port = Number(args[++i]);
    } else if (args[i] === '--allow-origin') {
      if (!args[i + 1]) throw Error('Missing --allow-origin value.');
      additional.push(args[++i]);
    } else {
      throw Error('Unknown option: ' + args[i] + '. Use --help.');
    }
  }
  if (!Number.isInteger(port) || port < 1024 || port > 65525) throw Error('Invalid port (1024–65525).');
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
let allowedOrigins;
try { allowedOrigins = [...new Set([...DEFAULT_ORIGINS, ...additional.map(parseOrigin)])]; }
catch (error) { console.error(error.message); process.exit(1); }

async function main() {
  const server = createProxyServer({port, allowedOrigins});
  try {
    const actual = await listen(server, port);
    console.log(`Universal Local HTTP Proxy v${VERSION}
[OK] Listening on 127.0.0.1:${actual}

Local Proxy URL: http://localhost:${actual}
Health: http://localhost:${actual}/health

Allowed browser origins:
${allowedOrigins.map(o => '  ' + o).join('\n')}

Press Ctrl+C to stop.`);
    let closing = false;
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
      if (closing) return;
      closing = true;
      console.log('\nStopping local proxy...');
      server.close(() => process.exit(0));
      setTimeout(() => { server.closeAllConnections(); process.exit(0); }, 5000).unref();
    });
  } catch (error) {
    console.error('Unable to start proxy:', error.message);
    process.exitCode = 1;
  }
}
main();
