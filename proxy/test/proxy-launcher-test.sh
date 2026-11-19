#!/bin/sh
# Offline bootstrap integration: sh proxy/test/proxy-launcher-test.sh
# Uses fixture archives and a fake runtime; never downloads or installs software.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/proxy-launcher-test.XXXXXXXX")
cleanup() { case "$work" in */proxy-launcher-test.*) rm -rf -- "$work";; *) exit 1;; esac; }
trap cleanup 0
mkdir -p "$work/bin"
export FIXTURE_ROOT="$work"
cat > "$work/bin/node" <<'EOF'
#!/bin/sh
printf 'false\n'
EOF
cat > "$work/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) printf '%s\n' "$FIXTURE_OS";; -m) printf '%s\n' "$FIXTURE_ARCH";; esac
EOF
cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
echo download >> "$FIXTURE_ROOT/network"
while [ "$1" != '-o' ]; do shift; done
target=$2
case "$target" in
  */SHASUMS256.txt) cp "$FIXTURE_ROOT/SHASUMS256.txt" "$target";;
  *) cp "$FIXTURE_ROOT/archive.tar.gz" "$target";;
esac
EOF
cat > "$work/bin/sw_vers" <<'EOF'
#!/bin/sh
printf '15.0\n'
EOF
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
for platform in darwin-arm64 darwin-x64 linux-x64; do
  case "$platform" in darwin-*) FIXTURE_OS=Darwin;; *) FIXTURE_OS=Linux;; esac
  case "$platform" in *arm64) FIXTURE_ARCH=arm64;; *) FIXTURE_ARCH=x86_64;; esac
  export FIXTURE_OS FIXTURE_ARCH
  project="$work/$platform/project with spaces"
  mkdir -p "$project/src"
  cp "$root/proxy-start-unix.sh" "$project/"
  touch "$project/src/proxy-cli.js"
  rm -f "$work/network"
  if printf 'n\n' | sh "$project/proxy-start-unix.sh" > "$work/output" 2>&1; then echo 'Refusal accepted unexpectedly'; exit 1; fi
  grep -q 'Installation declined' "$work/output"
  [ ! -e "$work/network" ]
  if sh "$project/proxy-start-unix.sh" < /dev/null > "$work/output" 2>&1; then echo 'EOF accepted unexpectedly'; exit 1; fi
  [ ! -e "$work/network" ]
  name="node-v24.22.3-$platform"
  mkdir -p "$work/archive/$name/bin"
  cat > "$work/archive/$name/bin/node" <<'EOF'
#!/bin/sh
case "$1" in
  -p) printf 'true\n';;
  --version) printf 'v24.22.3\n';;
  *) printf '%s\n' "$@" > "$FIXTURE_ROOT/arguments";;
esac
EOF
  chmod +x "$work/archive/$name/bin/node"
  tar -czf "$work/archive.tar.gz" -C "$work/archive" "$name"
  if command -v shasum >/dev/null 2>&1; then sum=$(shasum -a 256 "$work/archive.tar.gz"); else sum=$(sha256sum "$work/archive.tar.gz"); fi
  printf '%s  %s.tar.gz\n' "${sum%% *}" "$name" > "$work/SHASUMS256.txt"
  printf '\n' | sh "$project/proxy-start-unix.sh" --allow-origin 'https://client.example' > "$work/output" 2>&1
  grep -q '55-65 MB' "$work/output"
  grep -q 'https://client.example' "$work/arguments"
  [ "$(wc -l < "$work/network" | tr -d ' ')" = 2 ]
  sh "$project/proxy-start-unix.sh" --version < /dev/null > "$work/output" 2>&1
  [ "$(wc -l < "$work/network" | tr -d ' ')" = 2 ]
  # Corrupt checksum must fail before extraction or runtime publication.
  mv "$project/.proxy-runtime/node" "$project/.proxy-runtime/saved-node"
  printf '%064d  %s.tar.gz\n' 0 "$name" > "$work/SHASUMS256.txt"
  if printf '\n' | sh "$project/proxy-start-unix.sh" > "$work/output" 2>&1; then echo 'Corrupt archive accepted'; exit 1; fi
  grep -q 'checksum mismatch' "$work/output"
  [ ! -e "$project/.proxy-runtime/node" ]
  printf '[PASS] %s: refusal, EOF, Enter install, arguments, reuse, checksum rejection\n' "$platform"
done
