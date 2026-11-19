# Universal HTTP Proxy

Small provider- and client-neutral HTTP relay for browser requests to public external HTTP(S) APIs without direct CORS support. No Docker, YAML, API registration, user account or HTTPS certificate required.

## Quick start

**macOS (Apple Silicon and Intel):** download/clone the complete repository and double-click `proxy/proxy-start-mac.command`. If executable permissions were lost when downloading a ZIP, run `sh proxy/proxy-start-mac.command` in Terminal from the repository root. No Homebrew or administrator password is needed. Automatic installation of Node.js 24 requires macOS 13.5+, as specified in [Node.js platform requirements](https://github.com/nodejs/node/blob/v24.22.3/BUILDING.md#platform-list). Older systems need a compatible preinstalled Node.js 22+ or an OS update.

**Windows:** double-click `proxy/proxy-start-win.cmd`. It calls the PowerShell helper automatically.

**Linux:** run `sh proxy/proxy-start-unix.sh`.

Each entry point checks the proxy script and Node.js 22+. If a compatible Node.js is installed, it uses it. Otherwise it checks download/extraction/checksum utilities, reports the missing runtime, architecture, approximate download and disk sizes, and asks `Install ...? [Y/n]`. Press Enter to install, or type `n` to cancel. No runtime archive is downloaded before consent. The launcher downloads Node.js 24.22.3 from [the official release](https://nodejs.org/en/blog/release/v24.22.3/), checks SHA-256 against the official HTTPS checksum file, and extracts it into `proxy/.proxy-runtime/node`. This does not install a system package or change PATH. Later launches reuse it without downloading. macOS/Linux downloads are approximately 55–65 MB (250 MB free disk space); Windows downloads approximately 35–45 MB (200 MB free). Internet access is needed only when installing. The source launcher needs no npm packages.

Options are forwarded, for example `sh proxy/proxy-start-unix.sh --allow-origin https://client.example` or `proxy\proxy-start-win.cmd --allow-origin https://client.example`. Run these commands locally on the computer hosting the proxy. For unattended execution, provision Node.js first; absence of interactive approval stops installation.

Alternatively use a platform-matching executable from successful CI artifacts, such as `universal-http-proxy-win32-x64.exe`, without Node.js.

The console prints the active proxy URL, typically:

`http://localhost:8080`

The name describes a general HTTP relay. The supplied launcher can run on a laptop or server, but this version deliberately binds to loopback. A browser on a different computer cannot reach it directly. Public hosting needs a separately designed authenticated HTTPS ingress and deployment configuration; changing the name does not enable that mode.

The port falls back to the next available port in a short range if 8080 is occupied. Stop with Ctrl+C. Do not close the terminal while using the proxy.

## How it works

- Any trusted browser client chooses **per request** whether to use the proxy.
- With Proxy OFF, the browser accesses the original URL unchanged.
- With Proxy ON, the browser sends the original method, headers and body to `http://localhost:8080/proxy` and places the original complete URL in `X-Proxy-Target-URL`.
- The proxy validates origin, destination and DNS, then makes the outbound request and returns status, headers and a streamed body.
- Loopback and private network targets are intentionally blocked (SSRF protection). This is designed for external APIs, not for localhost webhooks.

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

Run `curl http://localhost:8080/health` to verify startup. To authorize `https://client.example`, launch `node src/proxy-cli.js --allow-origin https://client.example`. The `--allow-origin` option is repeatable and `PROXY_ALLOWED_ORIGINS` supports a comma-separated list. The `/proxy` endpoint requires an approved browser Origin (curl is not authorized by default). By default only loopback development origins (localhost/127.0.0.1 ports 3000/5173) are allowed. Explicitly authorize other websites using `--allow-origin` or `PROXY_ALLOWED_ORIGINS`.

For a curl smoke test to an external public endpoint after starting with `--allow-origin https://client.example`:

```bash
curl -i 'http://localhost:8080/proxy' -H 'Origin: https://client.example' -H 'X-Proxy-Target-URL: https://example.com/'
```

## API contract

`GET /health` returns `{"status":"ok","service":"universal-http-proxy","version":"1.0.0"}`.

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

**Privacy:** browser JavaScript still knows any API key entered in the browser UI. A proxy does not make a client-side secret confidential from the originating website.

## Problems and limitations

- **Browser reports CORS / Browser network-access:** check DevTools Network. Modern browsers may ask you to allow a public HTTPS site access to `localhost`. Grant access only to trusted websites. HTTP localhost works in many browsers but is not universally guaranteed.
- **Proxy not reachable:** check the console, active port and `/health`. If the port changed, update the proxy URL in your client application.
- **External 401/403:** verify provider credentials. Provider authentication is not bypassed.
- **Private destination blocked:** this is intentional. Do not disable browser security to work around it.
- **TLS failure:** the outbound server certificate must be trusted; TLS verification is never disabled.
- **EXE warned about by SmartScreen:** unsigned community executables may trigger prompts. Do not disable OS security; use the source launcher when uncertain.

Development: `cd proxy && npm test`. Building a platform executable: `npm install && npm run build:sea`, using Node 22 SEA, esbuild and postject. Build on each target operating system; binaries are not cross-compiled by the script. CI smoke-tests each executable's `--version` invocation, but tests in real browsers remain required.

HTTPS for localhost is not part of this version. Docker is not required or included.

Launcher verification: `npm test` covers the Windows entry point on Windows and offline Unix installation fixtures on Unix. From Git Bash on Windows, run `sh proxy/test/proxy-launcher-test.sh` from the repository root. Fixtures cover Apple Silicon/Intel archive selection, paths with spaces, refusal/EOF without downloads, Enter acceptance, runtime reuse and corrupt checksums. CI includes native `macos-15` (Apple Silicon) and `macos-15-intel` jobs, including actual runtime downloads and executable smoke checks. A configured CI job is not evidence of a completed run; Finder and OS security dialogs also require manual Mac verification.
