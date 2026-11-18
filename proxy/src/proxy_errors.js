export class ProxyError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function reportError(response, error, requestId) {
  if (response.headersSent) { response.destroy(); return; }
  const status = error instanceof ProxyError ? error.status : 502;
  const code = error instanceof ProxyError ? error.code : 'PROXY_TARGET_CONNECTION_ERROR';
  const message = error instanceof ProxyError ? error.message : 'Unable to reach the target API.';
  const body = Buffer.from(JSON.stringify({error:{code,message,requestId}}));
  response.writeHead(status, {'Content-Type':'application/json; charset=utf-8','Content-Length':body.length,'Cache-Control':'no-store'});
  response.end(body);
}
