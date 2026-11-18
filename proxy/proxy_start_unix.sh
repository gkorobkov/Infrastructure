#!/usr/bin/env sh
# Start the local proxy. Requires Node.js 22+; no dependencies or Docker.
set -eu
cd "$(dirname "$0")"
if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' 'Node.js 22+ is required: https://nodejs.org/' >&2
  exit 1
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$MAJOR" -lt 22 ]; then
  printf '%s\n' 'Node.js 22 or newer is required.' >&2
  exit 1
fi
printf '%s\n' 'Goal: launch the local HTTP proxy on loopback.' 'RUN: node src/proxy_cli.js'
exec node src/proxy_cli.js "$@"
