#!/usr/bin/env bash
# bb-stop.sh - Stop hook: record that the agent believes it finished.
# Note: the Stop payload has no exit code; COMPLETION.json (written by bb-run) is the only source of truth.
set -u
d="${BB_RUN_DIR:-}"
[ -z "$d" ] && exit 0
[ -d "$d" ] || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp="$d/STOP.json.tmp"
final="$d/STOP.json"
printf '{"at":"%s","source":"Stop","pid":%s}\n' "$ts" "$$" > "$tmp"
mv -f "$tmp" "$final"
exit 0
