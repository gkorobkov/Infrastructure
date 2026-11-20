import http from 'node:http';
import crypto from 'node:crypto';
import { ProxyError, reportError } from './proxy-errors.js';
import { forward } from './proxy-forward.js';
import { originAllowed, requireBrowserOrigin, safeHost } from './proxy-security.js';

export const DEFAULT_ORIGINS = [];
const methods = ['GET','POST','PUT','PATCH','DELETE','HEAD'];
const exposed = '*'; // credentialless fetch permits exposing all upstream response headers

export function createProxyServer(options={}) {
  const config = {
    allowedOrigins: options.allowedOrigins || DEFAULT_ORIGINS,
    port: options.port ?? 8080,
    lookupDns: options.lookupDns,
    ...(options.resolveTarget ? {resolveTarget:options.resolveTarget} : {}),
    connectTimeoutMs: options.connectTimeoutMs ?? 15000,
    idleTimeoutMs: options.idleTimeoutMs ?? 120000,
    maxBodyBytes: options.maxBodyBytes ?? 20*1024*1024,
  };
  const server = http.createServer(async(request,response)=>{
    const requestId = crypto.randomUUID();
    const started = Date.now();
    let errorCode;
    response.once('close', () => options.logger?.({
      event: 'request', requestId,
      method: methods.includes(request.method) || request.method === 'OPTIONS' ? request.method : 'OTHER',
      endpoint: ['/health', '/proxy'].includes(request.url) ? request.url : 'unknown',
      status: response.statusCode, completed: response.writableFinished,
      durationMs: Date.now() - started, ...(errorCode ? {errorCode} : {}),
      ...(request.headers.origin ? {originAllowed: originAllowed(request.headers.origin, config.allowedOrigins)} : {}),
    }));
    response.setHeader('X-Proxy-Request-ID',requestId);
    response.setHeader('X-Content-Type-Options','nosniff');
    const origin=request.headers.origin;
    if(originAllowed(origin,config.allowedOrigins)) {
      response.setHeader('Access-Control-Allow-Origin',origin);
      response.setHeader('Vary','Origin');
      response.setHeader('Access-Control-Expose-Headers',exposed);
    }
    try {
      const localPort=server.address()?.port || config.port;
      if(!safeHost(request.headers.host,localPort)) throw new ProxyError(403,'PROXY_HOST_FORBIDDEN','Invalid Host header.');
      if(request.url==='/health' && request.method==='GET') {
        const result=Buffer.from(JSON.stringify({status:'ok',service:'universal-http-proxy',version:'1.0.0'}));
        response.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Content-Length':result.length,'Cache-Control':'no-store'});response.end(result);return;
      }
      if(request.url!=='/proxy') throw new ProxyError(404,'PROXY_NOT_FOUND','Unknown proxy endpoint.');
      requireBrowserOrigin(request,config.allowedOrigins);
      if(request.method==='OPTIONS' && request.headers['access-control-request-method']) {
        const desired=request.headers['access-control-request-method'].toUpperCase();
        if(!methods.includes(desired)) throw new ProxyError(405,'PROXY_METHOD_NOT_ALLOWED','Unsupported method.');
        const wanted=request.headers['access-control-request-headers']||'';
        const headers=wanted.split(',').map(h=>h.trim().toLowerCase()).filter(Boolean);
        if(headers.some(h=>!httpToken(h) || h==='cookie' || h==='host' || h.startsWith('sec-') || h.startsWith('proxy-'))) throw new ProxyError(403,'PROXY_HEADER_FORBIDDEN','Forbidden preflight header.');
        response.setHeader('Access-Control-Allow-Methods',methods.join(', '));
        response.setHeader('Access-Control-Allow-Headers',headers.join(', '));
        response.setHeader('Access-Control-Max-Age','600');
        if(request.headers['access-control-request-private-network']==='true') response.setHeader('Access-Control-Allow-Private-Network','true');
        response.writeHead(204);response.end();return;
      }
      if(!methods.includes(request.method)) throw new ProxyError(405,'PROXY_METHOD_NOT_ALLOWED','Unsupported HTTP method.');
      await forward(request,response,config);
    } catch(error) { errorCode = error instanceof ProxyError ? error.code : 'PROXY_TARGET_CONNECTION_ERROR'; reportError(response,error,requestId); }
  });
  server.maxHeadersCount=100;
  server.headersTimeout=15000;
  server.requestTimeout=120000;
  return server;
}
function httpToken(value){return /^[!#$%&'*+.^_`|~0-9a-z-]+$/i.test(value);}

export async function listen(server,port=8080,host='127.0.0.1') {
  for(let candidate=port;candidate<=port+10;candidate++) {
    try {
      await new Promise((resolve,reject)=>{
        const fail=error=>{server.off('listening',resolve);reject(error);};
        server.once('error',fail);
        server.once('listening',()=>{server.off('error',fail);resolve();});
        server.listen(candidate,host);
      });
      return server.address().port;
    } catch(error) {if(error.code!=='EADDRINUSE'||candidate===port+10)throw error;}
  }
}
