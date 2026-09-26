# Dispatch Mechanics: How a Desktop Assistant Talks to the CLI

## The one command pattern

Everything in BuddyBridge reduces to this:

```
cd <project dir> && codebuddy -p -y --model <orchestrator> --fallback-model <backup> --effort <level> --max-turns <N> '<self-contained instruction>' > <run.log> 2>&1
```

| Flag | Why it's there |
|---|---|
| `cd <project dir>` first | Explicit working directory. There is **no `--cwd` flag** (verified: v2.158.0 rejects it) — cd decides the trusted-directory boundary and where relative paths land. Never rely on the session's current directory |
| `-p` | headless: runs to completion and exits. **One run = one brand-new session** (the agent remembers nothing from previous runs) |
| `-y` | bypassPermissions. Without it the headless agent cannot write files and gives up after one turn. **Not a permission-free pass** — see below |
| `--model` / `--fallback-model` | Orchestrator model (recommended: `kimi-k3-2`, supports xhigh) + overload backup (e.g. `glm-5.3`). `--fallback-model` is empirical — works in practice, undocumented officially |
| `--effort` | Reasoning depth, no TUI needed. Runtime-legal values: `minimal, low, medium, high, xhigh, max, ultracode` (yes, `ultracode` — `--help` under-prints it; verified against the v2.158.0 bundle's validation whitelist). Engine A uses `ultracode`, Engine B uses `max` |
| `--max-turns` | Official hard stop-loss for non-interactive runs. Always set it, alongside the semantic `or stop after N turns` clause |
| `> <run.log> 2>&1` | stdout only flushes at the very end of a `-p` run — without a log file you're blind for the entire duration |

## What `-y` does and does not do

`-y` skips general approvals. But per the official permission-modes non-interactive table, **HIGH/CRITICAL dangerous commands may still "require confirmation" when `CODEBUDDY_IS_SANDBOX` is unset — and in headless mode there is no interactive entry, so they surface as refusals**. A plan item that needs `rm -rf`, `sudo`, `curl` downloads, or `git push` will fail silently mid-run and the goal loop will grind to the turn cap.

Design plans to avoid high-risk commands (BuddyBridge templates forbid them), keep the `deny` baseline from the install cards (deny outranks everything, including bypass), and if you genuinely need full pass — run inside a disposable container with process env `CODEBUDDY_IS_SANDBOX=1` + `-y` (officially flagged high-risk; the variable is process-env only, never injected from settings.json).

## Dispatching: what actually works today (v1)

**v1 form: the desktop assistant writes the command, you paste it into a real terminal.**

1. You say: *"Dispatch PLAN.md to the CLI"* (in WorkBuddy)
2. The assistant: runs the pre-flight checks (version, workflow switches, APPROVED.md gate for execution), then **hands you the exact command** — pre-filled with absolute paths, idempotency guard, turn caps, model routing
3. You paste it into your own terminal (PowerShell / any shell) and walk away
4. The assistant monitors the artifacts (PROGRESS.md / report skeletons / run.log) and reports progress in-chat
5. On completion it runs the three-point verification (goal state / ledger checksums / no orphan processes)

**Why not spawn the CLI from inside the desktop session (v1.1, blocked)?** We tested this exhaustively on Windows (2026-09-25, CLI v2.158.0) and hit a layered wall — recording it here because nobody else has documented it:

1. The desktop host injects `CODEBUDDY_CONFIG_DIR`, `CODEBUDDY_MCP_CONFIG` (the host's entire MCP cluster, including heavyweight servers) and friends into child shells. A CLI spawned from inside the session boots in "host-child mode": it reads the host's config dir and connects the host's MCP fleet — one test run ballooned to a **138,075-token prompt** (exact figure from the v2.158.0 model-request log, `prompt_tokens=138075`) and produced zero artifacts in 11 minutes.
2. Clearing the variables (via the `scripts/launch.*` launcher in this repo) re-boots the CLI in standalone mode, but plugin/marketplace initialization then fails (`SAFE_DELETE_BULK_GUARD` helper path unavailable → plugin pass incomplete → exit 1 with no output on some shells, or a hang on others).
3. A human-launched terminal (your own PowerShell window) has none of these variables and works perfectly — which is exactly why v1 rides on it.

The `scripts/launch.sh` / `launch.ps1` launchers are kept as the v1.1 exploration base for in-session dispatch (they already solve the env-var half; the plugin-init half remains open).

## Why not the alternatives

| Alternative | Why rejected (for now) |
|---|---|
| `--serve` HTTP API | Works, but a running serve instance appears to hold the auth lock — other CLI processes fail with `Authentication required` until it's killed (empirical observation, not officially documented). Fine for a dedicated box, bad for a daily-driver machine |
| `--bg` background sessions | On Windows the background session dies with its owning CLI process (officially documented) — wrong lifetime model for unattended runs |
| `daemon` | Designed for keep-warm / service registration, not one-shot dispatch; adds moving parts v1 doesn't need |
| Agent SDK (`@tencent-ai/agent-sdk`) | The "real" programmatic bridge — v2 roadmap. Overkill when file conventions + one command achieve the same loop |

## The stateless contract (why files are the API)

Because every `-p` run starts with zero memory:

- **Plans, briefs, reports, progress ledgers are the only shared state.** All paths in the instruction must be absolute; placeholder paths get politely refused by the agent (fail-safe, costs one wasted run).
- **Idempotency must be spelled out** in the goal text: read the progress file first; skip items whose artifacts exist with matching checksums. Ledger entries must be written *after* the artifact (never before — a crash between "done" and the actual file permanently skips a half-written artifact).
- **One run can't ask you questions** — if the agent stops to ask, it prints the question and **exits**. Follow up with `codebuddy --continue -p -y "<answer>"` — but beware: `--continue` **restores any unfinished goal** from that session. If you only want to ask something without resuming the goal, start a fresh `-p` run instead.
- **Interactive-TUI approval prompts differ from headless**: in the TUI, even `bypassPermissions` still gets grilled on HIGH/CRITICAL commands (the dangerous-command check sits earlier in the chain, interactive sessions only). In `-p` mode there is no dialog at all — actions are either allowed or refused. That's why headless is the lowest-interruption mode, **not** a permission-free one.

## Debugging a dispatched run

- `run.log` tail for the latest events (`Get-Content <log> -Tail 20` / `tail -20`)
- For Engine A (workflows): the orchestration script CodeBuddy wrote for your run is saved under `~/.codebuddy/projects/<session>/` — readable, diffable, editable, and re-runnable. It is the **only** window into "what did it actually orchestrate" in headless mode. Ask the agent for the path, or look for the newest file there.
- Long-lived streaming: `--output-format stream-json` (add `--input-format stream-json` for the long-connection form that receives background-task events). Plain one-shot `-p` does not emit cross-turn background-task events — poll files instead.
