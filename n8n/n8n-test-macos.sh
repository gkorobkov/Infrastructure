#!/bin/bash
# Verify macOS launcher configuration and deployment with isolated command mocks.
# Usage/example (from repository root): bash n8n/n8n-test-macos.sh
set -eo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/project with spaces" "$work/bin"
cp "$root/n8n-docker-compose-deploy-mac.sh" "$root/.env.local.example" "$root/n8n-compose-local.yaml" "$work/project with spaces/"
project="$work/project with spaces"
cat > "$work/bin/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF
cat > "$work/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$N8N_TEST_TRACE"
exit 0
EOF
cat > "$work/bin/open" <<'EOF'
#!/bin/bash
exit 0
EOF
cp "$work/bin/open" "$work/bin/curl"
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"
export N8N_TEST_TRACE="$work/trace"
launch() { bash "$project/n8n-docker-compose-deploy-mac.sh" "$@"; }
reject() {
    if launch check > "$work/rejected.log" 2>&1; then echo 'Expected rejection' >&2; exit 1; fi
    [[ ! -d "$project/.n8n_macos_lock" ]]
}
launch check
cp "$project/.env.local" "$work/original"
key=$(sed -n 's/^N8N_ENCRYPTION_KEY=//p' "$work/original")
token=$(sed -n 's/^N8N_RUNNERS_AUTH_TOKEN=//p' "$work/original")
[[ $key =~ ^[a-f0-9]{64}$ && $token =~ ^[a-f0-9]{64}$ && $key != "$token" ]]
launch check
cmp "$project/.env.local" "$work/original"
launch > "$work/deploy.log"
grep -q 'up -d --pull always' "$N8N_TEST_TRACE"
grep -q 'Local n8n is ready' "$work/deploy.log"
! grep -q "$key" "$work/deploy.log"
launch status
for setting in 'N8N_HOST=0.0.0.0' 'N8N_DOCKER_CONTEXT=remote' 'N8N_DATA_PATH=../outside' 'N8N_VERSION=latest' 'N8N_PORT=0'; do
    name=${setting%%=*}
    sed "s|^$name=.*|$setting|" "$work/original" > "$project/.env.local"
    reject
done
cp "$work/original" "$project/.env.local"
printf '\nN8N_PORT=5679\n' >> "$project/.env.local"
reject
cp "$work/original" "$project/.env.local"
printf '\nN8N_TEST=$(touch SHOULD_NOT_EXIST)\n' >> "$project/.env.local"
reject
[[ ! -e "$project/SHOULD_NOT_EXIST" ]]
cp "$root/.env.local.example" "$project/.env.local"
mkdir -p "$project/VLM_DATA"
touch "$project/VLM_DATA/config"
reject
cp "$work/original" "$project/.env.local"
launch check
cmp "$project/.env.local" "$work/original"
printf 'macOS launcher checks passed; no software installed or containers started.\n'
