# Universal Local HTTP Proxy

Small dependency-free runtime for forwarding selected browser HTTP requests to external APIs that do not allow the AI Agents Lab browser origin. No Docker, YAML, API registration, user account or HTTPS certificate required.

## Quick start

**Windows:** install Node.js 22 or newer, download/clone this repository and double-click `proxy/proxy_start_win.cmd`. On supported GitHub CI builds, you may instead download `ai-agents-local-proxy-win32-x64.exe` from workflow artifacts and run it directly without Node.js.

**Linux/macOS:** install Node.js 22+, then run `./proxy/proxy_start_unix.sh`. Alternatively use a platform-matching executable from successful CI artifacts.

The console prints the active proxy URL, typically:

`http://localhost:8080`

The port falls back to the next available port in a short range if 8080 is occupied. Stop with Ctrl+C. Do not close the terminal while using the proxy.

## How it works

- The AI Agents Lab UI chooses **per request** whether to use the local proxy.
- With Proxy OFF, the browser accesses the original URL unchanged.
- With Proxy ON, the browser sends the original method, headers and body to `http://localhost:8080/proxy` and places the original complete URL in `X-Proxy-Target-URL`.
- The proxy validates origin, destination and DNS, then makes the outbound request and returns status, headers and a streamed body.
- Local requests and private network targets are intentionally blocked (SSRF protection). This is designed for external APIs, not for localhost webhooks.

Example browser request:

```js
const result = await fetch('http://localhost:8080/proxy', {
  method: 'GET',
  headers: {
    'X-Proxy-Target-URL': 'https://example.com/api?x=1&x=2',
    'Accept': 'application/json'
  },
  credentials: 'omit'
});
```

Run `curl http://localhost:8080/health` to verify startup. The `/proxy` endpoint requires an approved browser Origin (curl is not authorized by default). The default allowed website is `https://ai-agents-lab.gkorobkov.ru` plus local frontend development origins.

For a curl smoke test to an external public endpoint:

```bash
curl -i 'http://localhost:8080/proxy' -H 'Origin: https://ai-agents-lab.gkorobkov.ru' -H 'X-Proxy-Target-URL: https://example.com/'
```

## API contract

`GET /health` returns `{"status":"ok","service":"ai-agents-local-proxy","version":"1.0.0"}`.

`GET|POST|PUT|PATCH|DELETE|HEAD /proxy` uses the full target URL supplied in `X-Proxy-Target-URL`. The browser can only send the request headers allowed by Fetch. Transport-specific and hop-by-hop headers are not forwarded. Request and response bodies are passed as streams; response HTTP status is preserved. Upstream 4xx/5xx are not transformed into proxy errors. The proxy does not persist or log credentials.

Proxy-generated errors use `{"error":{"code":"...","message":"...","requestId":"..."}}` with a suitable HTTP status. Redirects are followed after validating each destination; redirects requiring replay of a streaming body are rejected. Credential headers are removed on cross-origin redirects.

SSE (text/event-stream), JSON, multipart/form-data, binary downloads, headers and query parameters are supported. Cookies and browser credentials are deliberately unsupported. For SSE use Fetch streams instead of EventSource, because the target URL must be supplied as a header.

## Security boundaries

- Listener binds to `127.0.0.1` only.
- Strict Host and Origin allowlists.
- Only HTTP and HTTPS upstream URLs.
- Private, loopback, link-local, special-purpose and metadata IP destinations are blocked, including IPv6.
- DNS results are validated and the actual network connection is pinned to a validated IP to prevent DNS rebinding.
- Redirect destinations are validated again.
- No arbitrary system file access, tunnelling, HTTP CONNECT or WebSocket support.
- No API keys or request/response bodies are stored in the proxy.

**Privacy:** browser JavaScript still knows any API key entered in the browser UI. A local proxy does not make a client-side secret confidential from the originating website.

## Problems and limitations

- **Browser reports CORS / Local Network Access:** check DevTools Network. Modern browsers may ask you to allow a public HTTPS site access to `localhost`. Grant access only to trusted websites. HTTP localhost works in many browsers but is not universally guaranteed.
- **Proxy not reachable:** check the console, active port and `/health`. If the port changed, update Proxy URL in AI Agents Lab.
- **External 401/403:** verify provider credentials. Provider authentication is not bypassed.
- **Private destination blocked:** this is intentional. Do not disable browser security to work around it.
- **TLS failure:** the outbound server certificate must be trusted; TLS verification is never disabled.
- **EXE warned about by SmartScreen:** unsigned community executables may trigger prompts. Do not disable OS security; use the source launcher when uncertain.

Development: `cd proxy && npm test`. Building a platform executable: `npm install && npm run build:sea`, using Node 22 SEA, esbuild and postject. Build on each target operating system; binaries are not cross-compiled by the script. CI smoke-tests each executable's `--version` invocation, but tests in real browsers remain required.

HTTPS for localhost is not part of this version. Docker is not required or included.
