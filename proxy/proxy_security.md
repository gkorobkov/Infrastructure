# Local Proxy Security Model

The proxy enables a trusted browser origin to call external APIs without depending on the external server's CORS response. This increases the origin's privileges: never add untrusted origins to the allowlist. The implementation accepts `/proxy` only when the request's Origin matches the allowlist. Nonbrowser clients can forge Origin; this is a defense-in-depth policy, not user authentication. Do not make the listener publicly accessible.

Threats addressed:

- **Local-network access / SSRF:** public IP checks on every DNS address, for IPv4 and IPv6, plus pinned DNS at socket connection time.
- **DNS rebinding:** the connection uses validated resolved addresses rather than resolving a second time.
- **Redirect SSRF:** each Location target is rechecked, credentials removed on cross-origin redirects, streaming bodies never silently replayed.
- **CSRF:** unknown/missing browser origins rejected and custom target header prevents ordinary cross-site form requests.
- **Host spoofing:** Host must match the loopback listener and actual port.
- **Sensitive data:** no logging of target URLs, headers or bodies; upstream response cookies are stripped.
- **Resource abuse:** header, request body, redirect and time constraints; network listener on loopback only.

Limitations: attacker processes already running on the same computer can forge Origin. Browser extension and XSS in an allowed origin can act with that origin's privileges. Browser request headers unavailable through Fetch cannot be transmitted. This proxy does not provide authentication, anonymity, encryption of local HTTP traffic, or a confidential server-side key vault. HTTPS localhost is a future optional feature.
