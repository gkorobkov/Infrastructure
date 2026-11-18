#!/usr/bin/env node
import { createProxyServer, listen, DEFAULT_ORIGINS } from './proxy_server.js';

const args=process.argv.slice(2);
if(args.includes('--help')||args.includes('-h')){
  console.log('AI Agents Local Proxy\nUsage: node src/proxy_cli.js [--port 8080] [--version] [--help]\n\nRuns a loopback HTTP proxy for allowed browser origins.');
  process.exit(0);
}
if(args.includes('--version')){console.log('1.0.0');process.exit(0);}
const index=args.indexOf('--port');
const port=index>=0?Number(args[index+1]):8080;
if(!Number.isInteger(port)||port<1024||port>65525){console.error('Invalid port (1024–65525).');process.exit(1);}
if(args.some(arg=>!['--port',String(port)].includes(arg))){console.error('Unknown option. Use --help.');process.exit(1);}
async function main() {
const server=createProxyServer({port});
try {
  const actual=await listen(server,port);
  console.log(`AI Agents Local HTTP Proxy v1.0.0\n[OK] Listening on 127.0.0.1:${actual}\n\nLocal Proxy URL: http://localhost:${actual}\nHealth: http://localhost:${actual}/health\n\nAllowed browser origins:\n${DEFAULT_ORIGINS.map(o=>'  '+o).join('\n')}\n\nPress Ctrl+C to stop.`);
  let closing=false;
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{
    if(closing)return;closing=true;
    console.log('\nStopping local proxy...');
    server.close(()=>process.exit(0));
    setTimeout(()=>{server.closeAllConnections();process.exit(0);},5000).unref();
  });
} catch(error){console.error('Unable to start proxy:',error.message);process.exitCode=1;}
}
main();
