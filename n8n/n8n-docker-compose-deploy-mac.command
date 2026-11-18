#!/bin/bash
# Start local n8n on macOS from Finder or Terminal.
# Usage: double-click, or bash n8n-docker-compose-deploy-mac.command [status|check].
# Example: bash ~/Infrastructure/n8n/n8n-docker-compose-deploy-mac.command
set -u
root="$(cd -- "$(dirname -- "$0")" && pwd -P)" || exit 1
printf 'Goal: Run the macOS local n8n launcher.\nRUN: /bin/bash %q' "$root/n8n-docker-compose-deploy-mac.sh"
if [[ $# -gt 0 ]]; then printf ' %q' "$@"; fi
printf '\n'
/bin/bash "$root/n8n-docker-compose-deploy-mac.sh" "$@"
result=$?
if [[ -t 0 ]]; then
    read -r -p "Press Enter to close this window. " || true
fi
exit "$result"
