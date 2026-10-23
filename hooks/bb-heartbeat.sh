#!/usr/bin/env bash
# bb-heartbeat.sh - PostToolUse hook: write a heartbeat for the active bb-run
# Requires BB_RUN_DIR env var (set by bb-run.ps1). Silent no-op when absent.
set -u
d="${BB_RUN_DIR:-}"
[ -z "$d" ] && exit 0
[ -d "$d" ] || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
seq=0
if [ -f "$d/.hbseq" ]; then
  seq=$(cat "$d/.hbseq" 2>/dev/null || echo 0)
fi
case "$seq" in ''|*[!0-9]*) seq=0 ;; esac
seq=$((seq + 1))
printf '%s' "$seq" > "$d/.hbseq"

tmp="$d/HEARTBEAT.json.tmp"
final="$d/HEARTBEAT.json"
printf '{"seq":%s,"at":"%s","source":"PostToolUse","pid":%s}\n' "$seq" "$ts" "$$" > "$tmp"
mv -f "$tmp" "$final"
exit 0
