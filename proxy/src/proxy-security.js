import dns from 'node:dns/promises';
import net from 'node:net';
import { ProxyError } from './proxy-errors.js';

const blocked = new net.BlockList();
for (const [network, prefix] of [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24],
  ['192.0.2.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15],
  ['198.51.100.0', 24], ['203.0.113.0', 24], ['224.0.0.0', 4],
  ['240.0.0.0', 4],
]) blocked.addSubnet(network, prefix, 'ipv4');
for (const [network, prefix] of [
  ['::', 128], ['::1', 128], ['::', 96], ['64:ff9b::', 96],
  ['100::', 64], ['2001::', 32], ['2001:db8::', 32],
  ['fc00::', 7], ['fe80::', 10], ['ff00::', 8],
]) blocked.addSubnet(network, prefix, 'ipv6');

export function isPublicIP(address) {
  let family = net.isIP(address);
  if (!family) return false;
  if (family === 6) {
    const v4 = address.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i);
    if (v4) return isPublicIP(v4[1]);
    // IPv4-compatible and mapped forms, unspecified and translation ranges are blocked above.
  }
  return !blocked.check(address, `ipv${family}`);
}

export function parseTarget(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 8192) {
    throw new ProxyError(400, 'PROXY_INVALID_TARGET_URL', 'A valid X-Proxy-Target-URL is required.');
  }
  let url;
  try { url = new URL(value); } catch { throw new ProxyError(400, 'PROXY_INVALID_TARGET_URL', 'Invalid target URL.'); }
  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password || url.hash) {
    throw new ProxyError(400, 'PROXY_INVALID_TARGET_URL', 'Target must be an HTTP(S) URL without credentials or fragment.');
  }
  return url;
}

export async function resolvePublicTarget(url, lookup = dns.lookup) {
  const host = url.hostname.replace(/^\[|\]$/g, '').replace(/\.$/, '');
  if (!host || host.toLowerCase() === 'localhost' || host.toLowerCase().endsWith('.localhost') || host.toLowerCase().endsWith('.local')) {
    throw new ProxyError(403, 'PROXY_TARGET_FORBIDDEN', 'Local targets are blocked.');
  }
  const ipFamily = net.isIP(host);
  let addresses;
  try { addresses = ipFamily ? [{address: host, family: ipFamily}] : await lookup(host, {all: true, verbatim: true}); }
  catch { throw new ProxyError(502, 'PROXY_TARGET_DNS_ERROR', 'Unable to resolve the target hostname.'); }
  if (!addresses?.length) throw new ProxyError(502, 'PROXY_TARGET_DNS_ERROR', 'Target hostname has no usable DNS addresses.');
  if (addresses.some(({address}) => !isPublicIP(address))) {
    throw new ProxyError(403, 'PROXY_TARGET_FORBIDDEN', 'Target resolves to a non-public network address.');
  }
  // Pin the connection to an address that was just validated. Never resolve DNS again in the HTTP client.
  const selected = addresses[0];
  return (_hostname, options, callback) => options?.all ? callback(null, [{address:selected.address,family:selected.family}]) : callback(null, selected.address, selected.family);
}

export function originAllowed(value, allowedOrigins) {
  return typeof value === 'string' && allowedOrigins.includes(value);
}

export function safeHost(header, port) {
  return header === `localhost:${port}` || header === `127.0.0.1:${port}`;
}

const hop = new Set(['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade']);
const requestBlocked = new Set(['host','content-length','origin','referer','cookie','cookie2','forwarded','x-forwarded-for','x-forwarded-host','x-forwarded-proto','via','x-proxy-target-url','access-control-request-method','access-control-request-headers','access-control-request-private-network']);
const responseBlocked = new Set(['set-cookie','set-cookie2','access-control-allow-origin','access-control-allow-methods','access-control-allow-headers','access-control-allow-credentials','access-control-expose-headers','access-control-allow-private-network']);

export function filterHeaders(source, direction) {
  const omit = new Set(hop);
  const connection = source.connection;
  if (connection) for (const key of String(connection).split(',')) omit.add(key.trim().toLowerCase());
  for (const key of (direction === 'request' ? requestBlocked : responseBlocked)) omit.add(key);
  const cleaned = {};
  for (const [name, value] of Object.entries(source)) {
    const key = name.toLowerCase();
    if (omit.has(key) || key.startsWith('sec-') || (direction === 'request' && key.startsWith('proxy-'))) continue;
    if (value !== undefined) cleaned[name] = value;
  }
  return cleaned;
}

export function requireBrowserOrigin(request, origins) {
  if (!originAllowed(request.headers.origin, origins)) {
    throw new ProxyError(403, 'PROXY_ORIGIN_FORBIDDEN', 'Origin is missing or not allowed.');
  }
}
