# Local Proxy HTTP Contract v1.0

**Purpose:** universal forward HTTP proxy for individual requests from a trusted web UI. External API target is supplied by request, not configured in the daemon.

1. Default listener: `127.0.0.1:8080`; automatic fallback to the next 10 ports.
2. Health: `GET /health` without credentials; response JSON with service name, status and version.
3. Request: `METHOD /proxy`, `X-Proxy-Target-URL: <absolute HTTP(S) URL>`, native end-to-end request headers and original request body stream.
4. Response: original HTTP status; allowed end-to-end response headers; original byte stream, with no forced JSON serialization or decompression. `Set-Cookie` and upstream CORS headers are intentionally removed.
5. CORS: exact Origin allowlist, `OPTIONS` preflight, no browser credentials; `Access-Control-Expose-Headers: *` for credentialless fetch. Local Network Access preflight recognized for allowed origins.
6. No implicit direct fallback. When proxy fails, the originating UI must report the failure.
7. Security: valid HTTP(S) targets only, no embedded userinfo, no internal address, no unknown origins, no unsafe Host header, DNS pinning, redirect validation, basic resource caps.
8. Supported: JSON, text, form bodies, multipart, binary, SSE, GET/POST/PUT/PATCH/DELETE/HEAD. Not supported: WebSockets, CONNECT, local/private targets, arbitrary browser-forbidden headers, cookies/credentials.
9. Deployment: Node.js 22+ launcher or optional Node SEA executable, no Docker or persistent configuration.
10. Tests: local in-process upstream simulator injected via the test harness; actual production SSRF protections separately unit-tested.
