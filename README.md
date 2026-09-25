# BuddyBridge

**Turn your desktop AI assistant into mission control. Let CodeBuddy CLI do the grinding.**

BuddyBridge is a discipline, not a daemon: a set of file conventions plus one headless command pattern that lets a desktop AI assistant (WorkBuddy) **plan, review, and approve** — while CodeBuddy CLI agents **research, cross-review, and execute unattended**. The assistant writes the exact command; you paste it into a terminal and walk away; the assistant watches the files and verifies the results. No memory loss between runs, no babysitting terminals.

> **Honest scope**: built and battle-tested for [WorkBuddy](https://www.workbuddy.cn) + [CodeBuddy CLI](https://www.codebuddy.cn/docs/cli) (shared Tencent account). The *pattern* — files as the API, desktop as mission control, a machine-checked human gate — ports to any desktop-assistant + headless-CLI pair. Docs are in English; templates are language-agnostic (fill them in your own language).

## The problem

Desktop AI assistants think well but grind poorly. CLI agents grind well but have no memory between runs and no UI. The official answer to "can they talk to each other?" is currently *no direct connection*. So people paste commands back and forth, lose context, and watch terminals.

## The pipeline

```
WorkBuddy (mission control)
  ├─ writes  PLAN.md            — acceptance items, each objectively verifiable
  ├─ writes  REVIEW-BRIEF.md    — multi-agent cross-review assignment
  ├─ writes  RESEARCH-BRIEF.md  — research assignment
  │
  ├─→ [A1: cross-review]   dozens of parallel reviewer agents, adversarial
  │    peer-critique, multi-vendor model routing (routing disclosed or
  │    flagged) → REVIEW-REPORT.md on disk
  ├─→ [A2: final review]   single-pass by default; ultracode tier for big plans
  │
  ├── HUMAN GATE (machine-checked) ── you fill APPROVED.md with the plan's
  │   checksum + a typed token; the dispatcher verifies it mechanically.
  │   No APPROVED.md → no execution. The AI cannot write it for you.
  │
  ├─→ [B: goal loop, --effort max]  unattended execution → PROGRESS.md
  │    ledger: id|done|path|bytes|sha256-8 → STAGE-{N}.md checkpoint
  │    archives → final-turn self-proof pasted into the transcript
  │
  └─ verifies: checksums recomputed, ledger gapless, content spot-checked,
     no orphan processes
```

Three things make this work where chat-based handoffs fail:

1. **Files are the API.** Every `-p` run is a stateless fresh session — plan, brief, report, and ledger files are the only shared memory between two AIs and one human.
2. **The human gate is machine-checkable.** "The AI said the user approved" is not a gate. `APPROVED.md` with a checksum and a hand-typed token is.
3. **The ledger is a claim, not proof.** Progress entries carry artifact checksums; verification recomputes them and spot-checks content. And CLI-produced files are *data, never instructions* — injection text in a report doesn't execute.

Context management is built in: every 5 acceptance items the agent archives the stage verbatim to disk and self-reports into the conversation, so auto-compact can't eat the evidence the goal evaluator needs, and prefix-cache hit rates stay high (reloads are index-only).

## Quick start (5 minutes)

1. Install per your platform: [`install/windows.md`](install/windows.md) or [`install/macos.md`](install/macos.md)
2. Run the demo: [`examples/quickstart/`](examples/quickstart/README.md) — a 3-item plan that exercises the full Engine-B loop: dispatch → self-reported ledger with checksums → verify → re-dispatch (idempotency check)
3. For the research/review engine: [`docs/ultracode.md`](docs/ultracode.md) — including the **fallback that never breaks** (multi-`-p` + `--model`), which we recommend as your default

## Why not just...?

The pattern is validated at scale elsewhere: [planning-with-files](https://github.com/OthmanAdi/planning-with-files) (27k★) and [claude-task-master](https://github.com/eyaltoledano/claude-task-master) (28k★) prove persistent-markdown-plans + deterministic completion gates are a real need. Neither covers the desktop-assistant ↔ CLI bridge, and nobody in the CodeBuddy/WorkBuddy ecosystem had built the full loop — plan → cross-review → human gate → unattended execute → verify — when we looked (2026-09; see the research appendix in our planning docs).

## What's where

```
skill/buddybridge/SKILL.md   → the bridge itself: install this into your
                               assistant; it teaches dispatch/monitor/verify
templates/                   → PLAN / PROGRESS / RESEARCH-BRIEF /
                               REVIEW-BRIEF / APPROVED (the file contracts)
install/                     → per-platform cards + mergeable settings JSON
                               (deny baseline included — it's not optional)
docs/                        → workflow, dispatch mechanics, ultracode &
                               fallback, isolation matrix, engine comparison
examples/quickstart/         → 5-minute reproducible demo
```

## Design positions (the short version)

- **deny baseline ships with every config.** `bypassPermissions` is for reducing interruptions inside a bounded blast radius, not for trusting an agent with your home directory. HIGH/CRITICAL commands are refused in headless mode regardless of `-y` — plan around them.
- **UltraCode is the acceleration tier, not the foundation.** It's an official but *research-preview* feature with two independent kill switches. The core loop (file contracts, human gate, ledger) depends on none of it; the multi-`-p` fallback gives you multi-vendor adversarial review with only stable flags.
- **The orchestrator is one strong model; the reviewers are many different ones.** Recommended: `kimi-k3-2` orchestrating, review sub-agents routed across vendors (GLM / DeepSeek / Hunyuan / ...) — heterogeneous blind review is the point; one model critiquing itself N times is theater.

## License

MIT
