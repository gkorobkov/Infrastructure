#!/bin/sh
# Finder entry point. Double-click to check prerequisites and start the proxy.
cd "$(dirname "$0")" || exit 1
sh ./proxy-start-unix.sh "$@"
result=$?
if [ "$result" -ne 0 ]; then
  printf 'Startup failed (%s). Press Enter to close. ' "$result"
  read -r answer
fi
exit "$result"
