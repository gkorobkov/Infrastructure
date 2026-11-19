#!/usr/bin/env sh
# Check/install Node.js and start Universal HTTP Proxy on macOS or Linux.
# Usage: sh proxy/proxy-start-unix.sh [--allow-origin https://client.example]
set -eu
cd "$(dirname "$0")"
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
run() { printf 'Goal: %s\n' "$1"; shift; printf 'RUN:'; printf ' %s' "$@"; printf '\n'; "$@"; }
version=v24.22.3
runtime="$PWD/.proxy-runtime"
check_node() {
  [ -x "$1" ] || return 1
  supported=$("$1" -p 'Number(process.versions.node.split(".")[0]) >= 22' 2>/dev/null) || return 1
  [ "$supported" = true ]
}
printf '[CHECK] Proxy entry point: '
[ -f src/proxy-cli.js ] || fail 'Missing src/proxy-cli.js; download the complete repository.'
printf 'found\n[CHECK] Node.js 22+: '
node_path=$(command -v node || true)
if check_node "$runtime/node/bin/node"; then
  node_path="$runtime/node/bin/node"
elif ! check_node "$node_path"; then
  printf 'missing or unsupported\n'
  case "$(uname -s)" in Darwin) os=darwin;; Linux) os=linux;; *) fail 'Supported systems: macOS and Linux.';; esac
  if [ "$os" = darwin ]; then
    mac_version=$(sw_vers -productVersion)
    mac_major=${mac_version%%.*}
    mac_minor=${mac_version#*.}; mac_minor=${mac_minor%%.*}
    if [ "$mac_major" -lt 13 ] || { [ "$mac_major" -eq 13 ] && [ "$mac_minor" -lt 5 ]; }; then
      fail 'Bundled Node.js 24 requires macOS 13.5 or newer. Update macOS or provide a compatible Node.js 22+.'
    fi
    printf '[OK] macOS %s\n' "$mac_version"
  fi
  case "$(uname -m)" in arm64|aarch64) arch=arm64;; x86_64|amd64) arch=x64;; *) fail 'Supported architectures: arm64 and x64.';; esac
  for tool in curl tar awk mktemp; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool. Install the OS command-line utilities and retry."
    printf '[OK] %s found\n' "$tool"
  done
  if command -v shasum >/dev/null 2>&1; then hash_tool=shasum
  elif command -v sha256sum >/dev/null 2>&1; then hash_tool=sha256sum
  else fail 'Missing SHA-256 tool (shasum or sha256sum).'; fi
  printf '[OK] %s found\n' "$hash_tool"
  file="node-$version-$os-$arch.tar.gz"
  base="https://nodejs.org/dist/$version"
  printf 'Node.js %s (%s/%s) is needed. Download approximately 55-65 MB; allow 250 MB disk space.\nInstall into %s (no system changes)? [Y/n] ' "$version" "$os" "$arch" "$runtime"
  answer=''
  read -r answer || fail 'No input. Run interactively to approve installation.'
  case "$answer" in ''|y|Y|yes|YES) ;; *) fail 'Installation declined; proxy was not started.';; esac
  mkdir -p "$runtime"
  stage=$(mktemp -d "$runtime/install.XXXXXXXX")
  cleanup() { case "$stage" in "$runtime"/install.*) rm -rf -- "$stage";; *) fail 'Unsafe cleanup path.';; esac; }
  trap cleanup 0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  run 'Download official Node.js archive.' curl --fail --location --proto '=https' --tlsv1.2 --retry 2 -o "$stage/$file" "$base/$file"
  run 'Download official checksums.' curl --fail --location --proto '=https' --tlsv1.2 --retry 2 -o "$stage/SHASUMS256.txt" "$base/SHASUMS256.txt"
  expected=$(awk -v name="$file" '$2 == name {print $1}' "$stage/SHASUMS256.txt")
  [ "${#expected}" -eq 64 ] || fail 'Missing archive checksum.'
  printf 'Goal: Verify archive SHA-256.\nRUN: %s (SHA-256)\n' "$hash_tool"
  if [ "$hash_tool" = shasum ]; then actual=$(shasum -a 256 "$stage/$file"); else actual=$(sha256sum "$stage/$file"); fi
  [ "${actual%% *}" = "$expected" ] || fail 'Archive checksum mismatch.'
  run 'Extract Node.js.' tar -xzf "$stage/$file" -C "$stage"
  check_node "$stage/node-$version-$os-$arch/bin/node" || fail 'Downloaded Node.js cannot run on this OS; check OS compatibility.'
  [ ! -e "$runtime/node" ] || fail 'An unusable bundled runtime exists. Move .proxy-runtime/node aside and retry.'
  mv "$stage/node-$version-$os-$arch" "$runtime/node"
  cleanup
  trap - 0 INT TERM
  node_path="$runtime/node/bin/node"
fi
printf '[OK] Node.js: %s\n' "$("$node_path" --version)"
printf 'Goal: Start Universal HTTP Proxy.\nRUN: node src/proxy-cli.js (requested options forwarded)\n'
exec "$node_path" src/proxy-cli.js "$@"
