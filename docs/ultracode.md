# UltraCode: The Research/Review Engine (and the fallback that never breaks)

UltraCode is CodeBuddy's built-in multi-agent orchestration mode. It is a **real, official feature** — but with two honest caveats the marketing gloss usually omits:

1. **Dynamic Workflow landed in v2.105.0** (not later), and the official docs flag it as **research-preview stage**.
2. It rides on `/config` switches ("Dynamic workflows" and "Ultracode keyword trigger" are **two independent toggles**) — either one off, and this engine is dead. Org policy `disableWorkflows: true` kills it too.

It is exposed to headless `codebuddy -p` runs (officially stated), **which is what makes it dispatchable from BuddyBridge** — with a timing caveat we flag below and a fallback that renders the caveat harmless.

## What UltraCode actually is

1. **Effort tier**: `--effort ultracode` is a **runtime-legal value** (the CLI's validation whitelist includes it; `--help` simply under-prints — verified against the v2.158.0 bundle). Setting it engages a session-level reminder interceptor that tells the model to plan a Dynamic Workflow first for every substantive request. This is the **preferred trigger** — stronger and steadier than the keyword.
2. **Keyword trigger**: the word `ultracode` in the user input (or plainly saying "use a workflow") triggers a single-shot workflow. Equivalent opt-in, weaker than the effort tier.
3. **`xhigh` reasoning** underneath, plus **Dynamic Workflow orchestration**: CodeBuddy writes a JavaScript orchestration script (deterministic sandbox: no `Date.now`, no `Math.random`, no dynamic eval; `require`/`process`/`Buffer` invisible) and the runtime executes it in the background — `agent()` spawns sub-agents, `parallel()` fans out (max 16 concurrent / 1000 per run; fewer on low-core machines), `phase()` groups stages.

The TUI describes it as **"xhigh + workflows"** — that's the accurate one-line definition. For Claude Code users: think **ultrathink + a built-in swarm**.

## Engine A vs Engine B: who holds the plan

| | Engine A — Workflow | Engine B — Goal loop |
|---|---|---|
| Plan lives in | the **script** (deterministic, re-runnable) | the evaluator's turn-by-turn judgment |
| Intermediate results | in script variables — never pollute the main context | in CodeBuddy's context window |
| Scale | dozens–hundreds of agents per run | a few delegations per turn |
| Quality patterns | **adversarial peer-critique**, multi-angle drafting + compare-select | single pass |
| Interruptible/resumable | pause/resume **within the same CLI session only**; process exit = run gone | goal state reloads with `--resume`; progress ledger on disk |
| Cost | can far exceed conversational for the same task | proportional to turns |

**Selection rule**: "many brains thinking in parallel and critiquing each other" (research, batch analysis, cross-review) → Engine A. "Work through a checklist in order and keep a ledger" (batch production, long unattended execution) → Engine B.

## The headless timing caveat (and why the fallback makes it moot)

Official docs state workflows work under `codebuddy -p`. They also state plain one-shot `-p` (process exits after the first result) **does not support background tasks** — and workflows belong to the background-task notification family. These two statements sit in tension: does a one-shot `-p` process wait for the workflow to finish before printing the result and exiting? Our baseline tests are on v2.158.0 (2026-09); **if your version's ultracode one-shot doesn't land its output file, don't debug it — switch to the fallback**.

**Verified on v2.158.0 (2026-09-25, Windows)**: `--effort ultracode` is accepted headless (no "unknown option") — the runtime whitelist is real. Behavioral finding: on a trivial task (list-directory-and-write-a-file), the agent **declined to orchestrate a workflow and answered directly** — ultracode's contract is "plan a workflow first for *substantive* requests", so simple tasks skip orchestration by design. Verdict: the effort tier engages; workflow orchestration on genuinely substantive tasks is the remaining unverified case, and the fallback below covers it either way.

Also note: for research runs, the official built-in `/deep-research` workflow already implements multi-angle search + cross-verification + claim-voting. Prefer it for standard research; use `ultracode` briefs when you need custom dimensions.

## The fallback (recommended default): multi-`-p`, multi-model, adversarial rounds

This needs **nothing** preview-flavored — only the stable `-p` + `--model` flags — so it works everywhere, forever:

```powershell
# Same REVIEW-BRIEF, one -p per dimension, each on a different vendor's model
cd <proj>
codebuddy -p -y --model <modelA> --max-turns 30 '按 <BRIEF> 只审「可行性+风险」，产出 <path>/REVIEW-A.md'
codebuddy -p -y --model <modelB> --max-turns 30 '按 <BRIEF> 只审「验收项可验证性+完整性」，产出 <path>/REVIEW-B.md'
codebuddy -p -y --model <modelC> --max-turns 30 '阅读 REVIEW-A.md 与 REVIEW-B.md，专挑两者结论的漏洞并反驳，产出 <path>/REVIEW-C.md'
```

Why this is the default recommendation, not a consolation prize:

- **Routing is guaranteed** — `--model` is a CLI flag, not a request to an improvised script. Multi-vendor blind review by construction.
- **Adversarial rounds by construction** — the third run's only job is attacking the first two.
- **No preview dependency** — the official vendor can reshuffle their preview features; this path never notices.

Treat single-shot `--effort ultracode` as the **acceleration tier** when it works; treat this as the floor that always does.

## Multi-vendor model routing (for workflow-mode reviews)

`agent(prompt, { model })` exists in the script API — but your brief is a natural-language *request* to an improvised script, which may or may not honor it, and an unavailable model may **silently fall back** to the session model (one model reviewing itself N times, dressed up as a blind review). Two guards, both in the templates:

1. **Mandatory disclosure**: the report's "execution metadata" section must list the actual model per agent; single-model runs must be flagged with reduced confidence.
2. **When routing must hold**: use the fallback above.

## Permissions & cost guards

- Workflow sub-agents always run `acceptEdits` (file edits auto-approved) and inherit your `allow` whitelist; shell/web-fetch/MCP calls outside the whitelist have no interactive entry in `-p` and get decided by the permission chain (usually refused). **Whitelist what the agents need before dispatch** — research runs need `WebSearch` **and** `WebFetch`.
- `-p` / Bypass / SDK never show the run-before-approval dialog — your "approval" is the human gate on the *report*, not on the run.
- **Cost**: one workflow run can cost multiples of a conversational approach. Guards: cost-gate fields in the brief (agent caps, fan-out caps, critique-round caps), `--max-turns` as a hard stop, and pilot-on-a-slice before scaling. Headless has no `/workflows` view — the only mid-run abort is killing the process, which does **not** guarantee preserving completed results. Choosing small slices beats stopping losses late.
- **Debugging**: each run's orchestration script lands under `~/.codebuddy/projects/<session>/` — the single window into what was actually orchestrated, readable and diffable. Ask the agent for the path.

## Disabling

Personal: `"disableWorkflows": true` in settings, or env `CODEBUDDY_DISABLE_WORKFLOWS=1`. Org: managed settings. Disabled = no `/deep-research`, no keyword trigger, no ultracode in the effort menu. Engine B (goal loop) is unaffected.
