#!/usr/bin/env bash
# bb-run.sh - BuddyBridge dispatch wrapper for macOS / Linux
# Same contract as bb-run.ps1 on Windows:
#   clean env -> isolated config -> stdin prompt (UTF-8 bytes) -> hard timeout
#   -> real exit code -> COMPLETION.json (ledger + verified[])
# Gate: APPROVED.md with dispatch_sha256 covering PLAN.md + PROMPT.md,
#       status approved -> used at claim time (dry-run never consumes).
#
# Usage:
#   ./bb-run.sh --workdir <dir> [--effort high] [--model kimi-k3-2]
#               [--max-turns 40] [--timeout 3600] [--skip-gate] [--dry-run]
set -uo pipefail

WORKDIR=""
EFFORT="high"
MODEL="kimi-k3-2"
MAX_TURNS=40
TIMEOUT=3600
SKIP_GATE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) WORKDIR="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --skip-gate) SKIP_GATE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "[bb-run] unknown arg: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "[bb-run] BLOCKED: $1" >&2; exit "$2"; }

[ -n "$WORKDIR" ] || fail "--workdir is required" 2
[ -d "$WORKDIR" ] || fail "WorkDir not found: $WORKDIR" 2
WORKDIR="$(cd "$WORKDIR" && pwd)"

PLAN="$WORKDIR/PLAN.md"
PROMPT="$WORKDIR/PROMPT.md"
PROGRESS="$WORKDIR/PROGRESS.md"
APPROVE="$WORKDIR/APPROVED.md"
BBROOT="$HOME/.buddybridge"
HOMECFG="$BBROOT/home"
RUNID="$(date +%Y%m%d-%H%M%S)"
RUNDIR="$WORKDIR/.buddybridge/runs/$RUNID"
mkdir -p "$RUNDIR" "$HOMECFG"
LOG="$RUNDIR/run.log"
COMPLETION="$RUNDIR/COMPLETION.json"

[ -f "$PROMPT" ] || fail "PROMPT.md missing - write the task text to that file (see templates/PROMPT.md)" 3

# Copy the prompt ONCE. The fingerprint and stdin both use this exact copy,
# so "verify A, execute B" is impossible.
PROMPT_COPY="$RUNDIR/prompt.bin"
cp "$PROMPT" "$PROMPT_COPY"

# ---------- preflight (before claiming any approval) ----------
command -v codebuddy >/dev/null 2>&1 || fail "codebuddy not in PATH" 19
command -v node >/dev/null 2>&1 || fail "node not in PATH" 20

CB_SRC="$(command -v codebuddy)"
# codebuddy is usually a symlink into the npm global package
CB_REAL="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$CB_SRC" 2>/dev/null || echo "$CB_SRC")"
NPMROOT="$(cd "$(dirname "$CB_REAL")/.." 2>/dev/null && pwd)"
PKGBIN=""
for cand in \
  "$NPMROOT/lib/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy" \
  "$NPMROOT/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy" \
  "/usr/local/lib/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy" \
  "/opt/homebrew/lib/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy"
do
  if [ -f "$cand" ]; then PKGBIN="$cand"; break; fi
done
# No hard fail here: when the package entry is not found we simply invoke the
# `codebuddy` command itself (it has a shebang and works the same way).

# ---------- guard settings must live in the isolated config dir ----------
# Done BEFORE the gate: a broken template must never burn an approval.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$REPO_ROOT/install/settings.macos.json"
BBSETTINGS="$HOMECFG/settings.json"
if [ -f "$TPL" ]; then
  if ! node -e 'const fs=require("fs");const s=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));fs.writeFileSync(process.argv[2],JSON.stringify(s,null,2))' "$TPL" "$BBSETTINGS" 2>"$RUNDIR/settings-error.log"; then
    fail "settings template is not valid JSON: $TPL (see $RUNDIR/settings-error.log)" 21
  fi
fi

# Portable SHA-256: macOS ships `shasum`, Linux `sha256sum`, fallback `openssl`.
sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'
  fi
}
sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else openssl dgst -sha256 | awk '{print $NF}'
  fi
}

# ---------- gate: APPROVED.md ----------
GATE_STATUS="skipped"
GATE_CLAIMED=0
if [ "$SKIP_GATE" -eq 0 ]; then
  [ -f "$APPROVE" ] || fail "APPROVED.md missing" 10
  [ -f "$PLAN" ] || fail "PLAN.md missing" 11

  # field extraction: anchored at line start, case-insensitive, optional "- " / "* " bullet
  field() {
    grep -iE "^[[:space:]]*[-*]?[[:space:]]*$1[[:space:]]*:[[:space:]]*" "$APPROVE" | head -1 \
      | sed -E "s/^[[:space:]]*[-*]?[[:space:]]*$1[[:space:]]*:[[:space:]]*//I" | tr -d '\r' | xargs
  }
  DECLARED="$(field dispatch_sha256)"
  TOKEN="$(field token)"
  STATUS="$(field status | tr '[:upper:]' '[:lower:]')"
  EXPIRES="$(field expires)"
  WDIR="$(field work_dir)"

  [ -n "$DECLARED" ] || fail "APPROVED.md has no dispatch_sha256 (it must cover PLAN.md + PROMPT.md)" 12
  [ -n "$TOKEN" ] || fail "APPROVED.md has no token" 13
  [ -n "$STATUS" ] || fail "APPROVED.md has no status" 14
  [ "$STATUS" = "approved" ] || fail "APPROVED.md status is \"$STATUS\" (expected approved; used means already consumed)" 15

  if [ -n "$EXPIRES" ]; then
    EXP_TS="$(python3 -c 'import sys,datetime;print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))' "$EXPIRES" 2>/dev/null || echo "")"
    if [ -n "$EXP_TS" ] && [ "$(date +%s)" -gt "$EXP_TS" ]; then
      fail "APPROVED.md expired" 16
    fi
  fi

  if [ -n "$WDIR" ]; then
    case "$WDIR" in
      "<"*|"("*|"（"*) : ;;   # unfilled placeholder = not bound
      *)
        NORM_DECL="$(printf '%s' "$WDIR" | sed 's#//*#/#g;s#/$##' | tr '[:upper:]' '[:lower:]')"
        NORM_ACT="$(printf '%s' "$WORKDIR" | sed 's#//*#/#g;s#/$##' | tr '[:upper:]' '[:lower:]')"
        [ "$NORM_DECL" = "$NORM_ACT" ] || fail "work_dir mismatch: approved for \"$WDIR\" but dispatching \"$WORKDIR\"" 18
        ;;
    esac
  fi

  PLAN_SHA="$(sha256_file "$PLAN")"
  PROMPT_SHA="$(sha256_file "$PROMPT_COPY")"
  ACTUAL="$(printf '%s:%s' "$PLAN_SHA" "$PROMPT_SHA" | sha256_stdin | cut -c1-12)"
  DECLARED_NORM="$(printf '%s' "$DECLARED" | tr '[:upper:]' '[:lower:]')"
  [ "$DECLARED_NORM" = "$ACTUAL" ] || fail "dispatch hash mismatch: approved=$DECLARED_NORM actual=$ACTUAL (covers PLAN.md + PROMPT.md)" 17

  if [ "$DRY_RUN" -eq 0 ]; then
    # claim-at-gate (NOT a lock: one WorkDir = one run at a time is an operating rule)
    TMP="$APPROVE.tmp"
    sed -E 's/^([[:space:]]*[-*]?[[:space:]]*status[[:space:]]*:[[:space:]]*)approved/\1used/I' "$APPROVE" > "$TMP"
    mv -f "$TMP" "$APPROVE"
    GATE_STATUS="used"
    GATE_CLAIMED=1
  else
    GATE_STATUS="approved (dry-run, not consumed)"
  fi
else
  echo "[bb-run] WARNING: gate SKIPPED - this dispatch has no approval and no plan lock" >&2
fi

# ---------- clean environment ----------
unset CODEBUDDY_MCP_CONFIG CODEBUDDY_SESSION_ID CODEBUDDY_CONVERSATION_REQUEST_ID \
      CODEBUDDY_MESSAGE_ID CODEBUDDY_TOOL_CALL_ID CODEBUDDY_ARTIFACTS \
      CODEBUDDY_SERVICE_PROXY_URL CODEBUDDY_FORCE_HEADLESS_BUNDLE \
      CODEBUDDY_FORCE_LITE_WB_BUNDLE CODEBUDDY_SKILL_TOOL_CHAR_BUDGET \
      CODEBUDDY_USE_POWERSHELL_TOOL
export CODEBUDDY_CONFIG_DIR="$HOMECFG"

# ---------- build command ----------
MCPFILE="$RUNDIR/empty-mcp.json"
printf '{"mcpServers":{}}' > "$MCPFILE"

if [ -n "$PKGBIN" ]; then
  set -- node "$PKGBIN" -p -y --effort "$EFFORT" --max-turns "$MAX_TURNS" \
          --output-format text --strict-mcp-config --mcp-config "$MCPFILE" \
          --model "$MODEL" --disallowedTools Bash
else
  set -- "$CB_SRC" -p -y --effort "$EFFORT" --max-turns "$MAX_TURNS" \
          --output-format text --strict-mcp-config --mcp-config "$MCPFILE" \
          --model "$MODEL" --disallowedTools Bash
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[bb-run] DRY RUN"
  echo "  cli    : $*"
  echo "  config : $HOMECFG"
  echo "  gate   : $GATE_STATUS"
  echo "  run    : $RUNDIR"
  exit 0
fi

# ---------- run with hard timeout ----------
START_TS="$(python3 -c 'import time;print(time.time())' 2>/dev/null || date +%s)"
START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

"$@" > "$LOG" 2>&1 < "$PROMPT_COPY" &
CLI_PID=$!
(
  sleep "$TIMEOUT"
  kill -TERM "$CLI_PID" 2>/dev/null
  sleep 5
  kill -KILL "$CLI_PID" 2>/dev/null
) &
WATCHDOG=$!

wait "$CLI_PID"
EXIT_CODE=$?
kill "$WATCHDOG" 2>/dev/null
wait "$WATCHDOG" 2>/dev/null

END_TS="$(python3 -c 'import time;print(time.time())' 2>/dev/null || date +%s)"
DURATION="$(python3 -c 'import sys;print(round(float(sys.argv[1])-float(sys.argv[2]),1))' "$END_TS" "$START_TS" 2>/dev/null || echo 0)"

STATUS="EXITED"
if [ "$EXIT_CODE" -gt 128 ]; then
  # killed by the watchdog -> normalize to the Windows convention
  STATUS="TIMEOUT"
  EXIT_CODE=124
fi

# ---------- verify ledger (wrapper computes hashes; the agent never has to) ----------
LEDGER_JSON="$(node - "$PROGRESS" <<'NODEEOF'
const fs = require('fs');
const crypto = require('crypto');
const file = process.argv[2];
const out = { verified: [], done: 0, failed: 0, missing_files: 0, hash_mismatch: 0, gaps: 0, gaps_skipped: false };
const ids = [];
if (fs.existsSync(file)) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(l => /^\d/.test(l));
  for (const line of lines) {
    const f = line.split('|');
    if (f.length < 3) continue;
    if (f[1] === 'done') out.done++;
    if (f[1] === 'failed') out.failed++;
    if (/^\d+$/.test(f[0])) ids.push(parseInt(f[0], 10));
    const p = f[2];
    if (!p) continue;
    if (fs.existsSync(p)) {
      const buf = fs.readFileSync(p);
      const real = crypto.createHash('sha256').update(buf).digest('hex');
      const entry = { id: f[0], status: f[1], path: p, exists: true, bytes: buf.length, sha256: real };
      const declared = (f[4] || '').trim().toLowerCase();
      if (/^[0-9a-f]{8}$/.test(declared)) {
        if (real.slice(0, 8) !== declared) { out.hash_mismatch++; entry.declared_mismatch = true; }
      } else if (/^[0-9a-f]{64}$/.test(declared)) {
        if (real !== declared) { out.hash_mismatch++; entry.declared_mismatch = true; }
      }
      out.verified.push(entry);
    } else {
      out.missing_files++;
      out.verified.push({ id: f[0], status: f[1], path: p, exists: false, bytes: 0, sha256: '' });
    }
  }
}
if (ids.length) {
  const maxId = Math.max(...ids);
  if (maxId > 100000) {
    out.gaps_skipped = true;
  } else if (maxId >= 1) {
    const seen = new Set(ids);
    for (let k = 1; k <= maxId; k++) if (!seen.has(k)) out.gaps++;
  }
}
process.stdout.write(JSON.stringify(out));
NODEEOF
)"

DONE="$(printf '%s' "$LEDGER_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.done)})')"
FAILED="$(printf '%s' "$LEDGER_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.failed)})')"
DIDWORK=0
if [ "$DONE" -gt 0 ] || [ "$FAILED" -gt 0 ]; then DIDWORK=1; fi
if printf '%s' "$LEDGER_JSON" | grep -q '"exists":true'; then DIDWORK=1; fi

# ---------- rollback decision ----------
CLAIM_ROLLBACK=0
if [ "$GATE_CLAIMED" -eq 1 ]; then
  if [ "$STATUS" = "ERROR" ]; then CLAIM_ROLLBACK=1; fi
  if [ "$STATUS" = "EXITED" ] && [ "$EXIT_CODE" -ne 0 ] && [ "$DIDWORK" -eq 0 ]; then
    FAST="$(python3 -c 'import sys;print(1 if float(sys.argv[1])<30 else 0)' "$DURATION" 2>/dev/null || echo 0)"
    if [ "$FAST" = "1" ]; then CLAIM_ROLLBACK=1; fi
  fi
fi

# ---------- COMPLETION.json ----------
LOGTAIL="$(tail -20 "$LOG" 2>/dev/null || true)"
export BB_RUNID="$RUNID" BB_STATUS="$STATUS" BB_EXIT="$EXIT_CODE" BB_STARTED="$START_ISO" \
       BB_DURATION="$DURATION" BB_EFFORT="$EFFORT" BB_MODEL="$MODEL" BB_TURNS="$MAX_TURNS" \
       BB_GATE="$GATE_STATUS" BB_ROLLBACK="$CLAIM_ROLLBACK" BB_LOG="$LOG" BB_LOGTAIL="$LOGTAIL" \
       BB_LEDGER="$LEDGER_JSON"
node <<'NODEEOF'
const fs = require('fs');
const path = require('path');
const e = process.env;
const ledger = JSON.parse(e.BB_LEDGER);
const completion = {
  run_id: e.BB_RUNID,
  status: e.BB_STATUS,
  exit_code: Number(e.BB_EXIT),
  started_at: e.BB_STARTED,
  finished_at: new Date().toISOString(),
  duration_sec: Number(e.BB_DURATION),
  effort: e.BB_EFFORT,
  model: e.BB_MODEL,
  max_turns: Number(e.BB_TURNS),
  gate: e.BB_GATE,
  claim_rolled_back: e.BB_ROLLBACK === '1',
  ledger: {
    done: ledger.done, failed: ledger.failed, missing_files: ledger.missing_files,
    hash_mismatch: ledger.hash_mismatch, gaps: ledger.gaps, gaps_skipped: ledger.gaps_skipped
  },
  verified: ledger.verified,
  log_path: e.BB_LOG,
  log_tail: e.BB_LOGTAIL
};
const out = path.join(path.dirname(e.BB_LOG), 'COMPLETION.json');
fs.writeFileSync(out + '.tmp', JSON.stringify(completion, null, 2));
fs.renameSync(out + '.tmp', out);
NODEEOF

# ---------- rollback (only when the CLI left nothing behind) ----------
if [ "$CLAIM_ROLLBACK" -eq 1 ]; then
  TMP="$APPROVE.tmp"
  sed -E 's/^([[:space:]]*[-*]?[[:space:]]*status[[:space:]]*:[[:space:]]*)used/\1approved/I' "$APPROVE" > "$TMP"
  mv -f "$TMP" "$APPROVE"
  echo "[bb-run] approval rolled back to approved (the CLI did no real work)" >&2
fi

MISSING="$(printf '%s' "$LEDGER_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).missing_files)})')"
MISMATCH="$(printf '%s' "$LEDGER_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).hash_mismatch)})')"
GAPS="$(printf '%s' "$LEDGER_JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).gaps)})')"

echo "[bb-run] $STATUS exit=$EXIT_CODE in ${DURATION}s"
echo "  ledger  : done=$DONE failed=$FAILED missing=$MISSING hash_mismatch=$MISMATCH gaps=$GAPS"
echo "  run dir : $RUNDIR"
exit "$EXIT_CODE"
