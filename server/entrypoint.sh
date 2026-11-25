#!/usr/bin/env bash
set -euo pipefail
export SURVIVOR_SHUTDOWN_FILE=/tmp/survivor-shutdown
rm -f "$SURVIVOR_SHUTDOWN_FILE"
godot --headless --path /opt/survivor --script res://server/main.gd &
game=$!
gateway=""
shutdown() {
  touch "$SURVIVOR_SHUTDOWN_FILE"
  if [[ -n "$gateway" ]]; then
    kill -TERM "$gateway" 2>/dev/null || true
  fi
  wait "$game" || return $?
}
trap 'shutdown; exit $?' TERM INT
for attempt in {1..180}; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$SURVIVOR_WS_PORT") 2>/dev/null; then
    break
  fi
  if ! kill -0 "$game" 2>/dev/null; then
    wait "$game"
    exit 1
  fi
  sleep .2
done
if [[ "$attempt" == 180 ]]; then
  shutdown || true
  exit 1
fi
caddy run --config /opt/Caddyfile --adapter caddyfile &
gateway=$!
status=0
wait -n "$game" "$gateway" || status=$?
shutdown || true
exit "$status"
