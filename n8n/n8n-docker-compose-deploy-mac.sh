#!/bin/bash
# Deploy local n8n and its task runner on macOS (Intel or Apple silicon).
# Usage: bash n8n-docker-compose-deploy-mac.sh [check|status]
# Example: bash ~/Infrastructure/n8n/n8n-docker-compose-deploy-mac.sh
# check validates configuration only; status queries Docker without starting it.
set -eo pipefail
umask 077

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run() {
    local purpose=$1; shift
    printf 'Goal: %s\nRUN:' "$purpose"
    printf ' %q' "$@"
    printf '\n'
    "$@"
}
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$root"
mode=${1:-deploy}
[[ $# -le 1 ]] || fail 'Usage: n8n-docker-compose-deploy-mac.sh [check|status]'
case "$mode" in deploy|check|status) ;; *) fail 'Usage: n8n-docker-compose-deploy-mac.sh [check|status]; use Ctrl+C to interrupt this launch.' ;; esac
[[ $(run 'Identify the operating system.' uname -s | tail -n 1) == Darwin ]] || fail 'This launcher requires macOS.'
# Finder may not inherit the terminal PATH; use Docker Desktop bundled tools.
export PATH="/Applications/Docker.app/Contents/Resources/bin:$HOME/Applications/Docker.app/Contents/Resources/bin:$HOME/.docker/bin:$PATH"
env_file="$root/.env.local"
compose_file="$root/n8n-compose-local.yaml"

if [[ $mode == status ]]; then
    command -v docker >/dev/null || fail 'Docker CLI not found. Install Docker Desktop.'
    run 'Inspect the local Docker Desktop engine without starting it.' docker --context desktop-linux info
    exit
fi

# Atomic directory creation prevents concurrent launches from rewriting secrets.
run 'Lock configuration initialization for this directory.' mkdir "$root/.n8n_macos_lock" || fail 'Another launch is active. If interrupted by a power loss, remove .n8n_macos_lock after checking no launcher is running.'
temp_file=''
cleanup() {
    [[ -z $temp_file ]] || rm -f -- "$temp_file"
    rmdir -- "$root/.n8n_macos_lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ ! -L $env_file ]] || fail '.env.local must not be a symbolic link.'
if [[ ! -f $env_file ]]; then
    run 'Create local settings from the public template.' cp -- "$root/.env.local.example" "$env_file"
fi

# Parse data, never source/eval an env file. Accept simple quoted values and CRLF.
keys=(); values=()
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ $line =~ ^(N8N_[A-Z0-9_]+)=(.*)$ ]] || fail 'Invalid env line; use N8N_NAME=value without shell expressions.'
    key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
    for existing in "${keys[@]}"; do [[ $existing != "$key" ]] || fail "Duplicate setting: $key"; done
    if [[ $value == \"*\" || $value == \'*\' ]]; then value=${value:1:${#value}-2}; fi
    [[ $value != *'$'* && $value != *'`'* && $value != *'"'* && $value != *"'"* ]] || fail "Unsupported characters in $key"
    keys+=("$key"); values+=("$value")
done < "$env_file"
for ((i=0; i<${#keys[@]}; i++)); do
    key=${keys[$i]}; value=${values[$i]}
    if [[ $value == GENERATE_ON_FIRST_RUN ]]; then
        # Refuse key generation if data already exists; it cannot decrypt old credentials.
        if [[ $key == N8N_ENCRYPTION_KEY && -d "$root/VLM_DATA" && -n $(ls -A "$root/VLM_DATA") ]]; then
            fail 'Existing VLM_DATA found. Restore the original encryption key in .env.local.'
        fi
        printf 'Goal: Generate an independent secret for %s.\nRUN: openssl rand -hex 32 (output hidden)\n' "$key"
        value=$(openssl rand -hex 32)
        [[ $value =~ ^[a-f0-9]{64}$ ]] || fail 'Secret generation failed.'
        values[$i]=$value
    fi
    # Explicit file values override inherited process variables for Compose.
    export "$key=$value"
done
for key in N8N_PROJECT_NAME N8N_HOST N8N_PORT N8N_VERSION N8N_DATA_PATH N8N_TIMEZONE N8N_OPEN_BROWSER N8N_DOCKER_CONTEXT N8N_DOCKER_TIMEOUT_SECONDS N8N_STARTUP_TIMEOUT_SECONDS N8N_ENCRYPTION_KEY N8N_RUNNERS_AUTH_TOKEN; do
    found=false
    for existing in "${keys[@]}"; do [[ $existing != "$key" ]] || found=true; done
    [[ $found == true && -n ${!key} ]] || fail "Missing required setting: $key"
done
[[ $N8N_HOST == 127.0.0.1 ]] || fail 'N8N_HOST must be 127.0.0.1.'
[[ $N8N_DOCKER_CONTEXT == desktop-linux ]] || fail 'N8N_DOCKER_CONTEXT must be desktop-linux.'
[[ $N8N_PROJECT_NAME =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail 'Invalid project name.'
[[ $N8N_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use an exact n8n version.'
[[ $N8N_DATA_PATH == ./VLM_DATA ]] || fail 'N8N_DATA_PATH must be ./VLM_DATA.'
[[ ! -L "$root/VLM_DATA" ]] || fail 'VLM_DATA must not be a symbolic link.'
[[ $N8N_OPEN_BROWSER == true || $N8N_OPEN_BROWSER == false ]] || fail 'N8N_OPEN_BROWSER must be true or false.'
for key in N8N_PORT N8N_DOCKER_TIMEOUT_SECONDS N8N_STARTUP_TIMEOUT_SECONDS; do
    value=${!key}
    [[ $value =~ ^[1-9][0-9]{0,4}$ ]] || fail "Invalid positive integer: $key"
    (( value <= 65535 )) || fail "Value too large: $key"
done
[[ $N8N_ENCRYPTION_KEY != "$N8N_RUNNERS_AUTH_TOKEN" ]] || fail 'Encryption key and runner token must differ.'

# Keep comments and all non-placeholder lines; secrets never enter command arguments.
temp_file=$(mktemp "$root/.n8n_env.XXXXXX")
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line =~ ^(N8N_[A-Z0-9_]+)=(.*)$ ]]; then
        key=${BASH_REMATCH[1]}; raw=${BASH_REMATCH[2]}
        if [[ $raw == GENERATE_ON_FIRST_RUN || $raw == '"GENERATE_ON_FIRST_RUN"' || $raw == "'GENERATE_ON_FIRST_RUN'" ]]; then line="$key=${!key}"; fi
    fi
    printf '%s\n' "$line"
done < "$env_file" > "$temp_file"
run 'Save local settings with owner-only permissions.' mv -- "$temp_file" "$env_file"
temp_file=''
if [[ $mode == check ]]; then printf 'Local macOS configuration checks passed. No containers started.\n'; exit; fi

if ! command -v docker >/dev/null; then
    printf 'Docker Desktop is missing. Install the Mac version for your processor from:\nhttps://docs.docker.com/desktop/setup/install/mac-install/\n'
    read -r -p 'Open the official installation page? [y/N] ' answer || answer=''
    if [[ $answer == y || $answer == Y ]]; then run 'Open Docker installation instructions.' open 'https://docs.docker.com/desktop/setup/install/mac-install/'; fi
    fail 'Install Docker Desktop, complete its onboarding, then run this launcher again.'
fi
run 'Start Docker Desktop; complete its agreement in the application.' open -a Docker
deadline=$((SECONDS + N8N_DOCKER_TIMEOUT_SECONDS))
while :; do
    printf 'Goal: Wait for the local Docker Desktop Linux engine.\nRUN: docker --context desktop-linux info (output hidden)\n'
    if docker --context desktop-linux info >/dev/null 2>&1; then break; fi
    (( SECONDS < deadline )) || fail 'Docker engine timeout. Complete Docker Desktop onboarding and rerun.'
    printf 'Waiting for Docker Desktop...\n'
    sleep 3
done
dc=(docker --context desktop-linux compose --project-directory "$root" --env-file "$env_file" -f "$compose_file" -p "$N8N_PROJECT_NAME")
run 'Check Docker Compose availability.' docker --context desktop-linux compose version
run 'Validate Compose without displaying secrets.' "${dc[@]}" config --quiet
run 'Create the persistent local data directory.' mkdir -p -- "$root/VLM_DATA"
if ! run 'Download images and start n8n and its runner.' "${dc[@]}" up -d --pull always; then
    run 'Show container state.' "${dc[@]}" ps || true
    fail 'Compose failed. Resolve the displayed error and rerun.'
fi
url="http://localhost:$N8N_PORT/"
deadline=$((SECONDS + N8N_STARTUP_TIMEOUT_SECONDS))
while :; do
    printf "Goal: Check n8n readiness.\nRUN: curl --noproxy '*' --fail --silent --show-error --max-time 5 http://127.0.0.1:%s/healthz/readiness\n" "$N8N_PORT"
    if curl --noproxy '*' --fail --silent --show-error --max-time 5 "http://127.0.0.1:$N8N_PORT/healthz/readiness" >/dev/null 2>&1; then break; fi
    (( SECONDS < deadline )) || { run 'Show container state.' "${dc[@]}" ps; fail 'n8n readiness timed out. Inspect Docker Desktop container logs.'; }
    printf 'Waiting for n8n...\n'
    sleep 3
done
printf 'Local n8n is ready. Open: %s\n' "$url"
if [[ $N8N_OPEN_BROWSER == true ]]; then run 'Open the ready n8n UI.' open "$url"; fi
