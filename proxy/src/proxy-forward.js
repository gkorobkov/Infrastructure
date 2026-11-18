import http from 'node:http';
import https from 'node:https';
import { pipeline } from 'node:stream/promises';
import { ProxyError } from './proxy-errors.js';
import { filterHeaders, parseTarget, resolvePublicTarget } from './proxy-security.js';

const redirects = new Set([301,302,303,307,308]);
function upstreamError(error) {
  if (error instanceof ProxyError) return error;
  if (['ETIMEDOUT', 'ESOCKETTIMEDOUT', 'UND_ERR_CONNECT_TIMEOUT'].includes(error.code)) {
    return new ProxyError(504, 'PROXY_TARGET_TIMEOUT', 'Target API request timed out.');
  }
  return new ProxyError(502, 'PROXY_TARGET_CONNECTION_ERROR', 'Unable to connect to the target API.');
}

function openUpstream(url, {method,headers,body,signal,connectTimeoutMs,idleTimeoutMs,lookup}) {
  return new Promise((resolve,reject) => {
    const transport = url.protocol === 'https:' ? https : http;
    const request = transport.request(url,{method,headers,lookup,agent:false,signal},response => resolve({request,response}));
    request.setTimeout(idleTimeoutMs, () => request.destroy(new ProxyError(504,'PROXY_TARGET_TIMEOUT','Target API connection was idle too long.')));
    const timeout = setTimeout(()=>request.destroy(new ProxyError(504,'PROXY_TARGET_TIMEOUT','Target API connection timed out.')),connectTimeoutMs);
    request.once('socket',socket => socket.once('connect',()=>clearTimeout(timeout)));
    request.once('close',()=>clearTimeout(timeout));
    request.once('error',reject);
    if (body) pipeline(body,request).catch(reject);
    else request.end();
  });
}

export async function forward(request,response,{lookupDns,connectTimeoutMs=15000,idleTimeoutMs=120000,maxRedirects=5,maxBodyBytes=20*1024*1024,resolveTarget=resolvePublicTarget}) {
  let target = parseTarget(request.headers['x-proxy-target-url']);
  let method = request.method;
  let headers = filterHeaders(request.headers,'request');
  let body = ['GET','HEAD'].includes(method) ? null : request;
  let redirected = 0;
  const abort = new AbortController();
  response.once('close',()=> { if (!response.writableFinished) abort.abort(); });
  request.once('aborted',()=>abort.abort());
  let count = 0;
  if (body) {
    // Limit raw request bytes without parsing or reserializing body.
    const {Transform} = await import('node:stream');
    const limiter = new Transform({transform(chunk,_enc,done){ count+=chunk.length; if(count>maxBodyBytes) done(new ProxyError(413,'PROXY_REQUEST_TOO_LARGE','Request body exceeds the configured limit.')); else done(null,chunk); }});
    body = request.pipe(limiter);
  }
  for (;;) {
    const lookup = await resolveTarget(target, lookupDns);
    let result;
    try {
      result = await openUpstream(target,{method,headers,body,signal:abort.signal,connectTimeoutMs,idleTimeoutMs,lookup});
    } catch(error) { throw upstreamError(error); }
    const upstream = result.response;
    if (redirects.has(upstream.statusCode) && upstream.headers.location) {
      if (++redirected > maxRedirects) { upstream.resume(); throw new ProxyError(502,'PROXY_REDIRECT_BLOCKED','Too many redirects.'); }
      const next = parseTarget(new URL(upstream.headers.location,target).href);
      // Cannot replay a streamed body. For 307/308, reject; for POST 301/302 and 303, switch to GET.
      const changeToGet = upstream.statusCode===303 && method!=='HEAD' || [301,302].includes(upstream.statusCode) && method==='POST';
      if (body && !changeToGet) { upstream.resume(); throw new ProxyError(502,'PROXY_REDIRECT_BLOCKED','Redirect requires replaying a request body.'); }
      if (target.origin !== next.origin) {
        for(const name of Object.keys(headers)) if (['authorization','api-key','x-api-key','cookie'].includes(name.toLowerCase())) delete headers[name];
      }
      if (changeToGet) {
        method='GET';body=null;
        for (const name of Object.keys(headers)) if (['content-type','content-length','content-encoding'].includes(name.toLowerCase())) delete headers[name];
      }
      upstream.resume();target=next;continue;
    }
    const replyHeaders = filterHeaders(upstream.headers,'response');
    response.writeHead(upstream.statusCode,replyHeaders);
    try { await pipeline(upstream,response); }
    catch(error) { if (!abort.signal.aborted) throw upstreamError(error); }
    return;
  }
}
