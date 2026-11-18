// Build a self-contained executable with Node 22 SEA and postject.
// Run: npm install && npm run build:sea (on each target OS).
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, writeFileSync, chmodSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root=join(dirname(fileURLToPath(import.meta.url)),'..');
const dist=join(root,'dist');
mkdirSync(dist,{recursive:true});
const cjs=join(dist,'proxy.bundle.cjs');
await build({entryPoints:[join(root,'src/proxy_cli.js')],outfile:cjs,bundle:true,platform:'node',target:'node22',format:'cjs',packages:'external',banner:{js:'// AI Agents Local Proxy bundled for Node SEA'}});
const blob=join(dist,'proxy.blob');
writeFileSync(join(dist,'sea-config.json'),JSON.stringify({main:cjs,output:blob,disableExperimentalSEAWarning:true}));
execFileSync(process.execPath,['--experimental-sea-config',join(dist,'sea-config.json')],{stdio:'inherit'});
const name=`ai-agents-local-proxy-${process.platform}-${process.arch}${process.platform==='win32'?'.exe':''}`;
const executable=join(dist,name);
copyFileSync(process.execPath,executable);
if(process.platform==='darwin')execFileSync('codesign',['--remove-signature',executable],{stdio:'inherit'});
const postject=join(root,'node_modules','postject','dist','cli.js');
execFileSync(process.execPath,[postject,executable,'NODE_SEA_BLOB',blob,'--sentinel-fuse','NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2'],{stdio:'inherit'});
if(process.platform==='darwin')execFileSync('codesign',['--sign','-','--force',executable],{stdio:'inherit'});
if(process.platform!=='win32')chmodSync(executable,0o755);
console.log('Built:',executable);
