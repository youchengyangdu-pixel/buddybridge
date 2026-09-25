# The BuddyBridge Workflow: Review → Finalize → Approve → Execute

BuddyBridge is not a daemon or a server. It is a **discipline** — a set of file conventions plus one headless command pattern — that turns any desktop AI assistant (built for WorkBuddy, portable to others) into a **mission control center** for CodeBuddy CLI agents.

## The problem it solves

Desktop AI assistants are great at thinking but bad at grinding; CLI agents are great at grinding but have no memory between runs and no UI for handing them work. The official answer to "can they talk to each other?" is currently *no direct connection* — so people copy-paste commands back and forth, lose context, and babysit terminals.

BuddyBridge closes that loop with file artifacts and one command template:

```
WorkBuddy (mission control — orchestrator model: kimi-k3-2 recommended)
  ├─ writes  PLAN.md            (checklist of verifiable acceptance items)
  ├─ writes  REVIEW-BRIEF.md    (multi-agent cross-review assignment)
  ├─ writes  RESEARCH-BRIEF.md  (research assignment)
  │
  ├─→ [Engine A1: cross-review]   ultracode workflow OR the guaranteed
  │    multi-`-p` fallback — adversarial peer-critique, multi-vendor
  │    model routing, model disclosure mandatory
  │    → REVIEW-REPORT.md lands on disk
  │
  ├─→ [A2: final review]  single --effort high pass by default;
  │    ultracode tier only for large projects
  │
  ├── HUMAN GATE ── machine-checked, not vibes ──
  │   the human fills APPROVED.md (PLAN checksum + random token);
  │   the dispatching AI verifies it mechanically before Engine B.
  │   No APPROVED.md → no execution. The AI cannot write it for you.
  │
  ├─→ [Engine B: Goal loop + --effort max]  unattended long-run execution
  │    → PROGRESS.md self-reported ledger: `id|done|path|bytes|sha256-8`
  │    → STAGE-{N}.md checkpoint archives every 5 items
  │    → final-turn self-proof commands pasted into the transcript
  │
  └─ verifies: checksums recomputed, ledger gapless, content spot-checked,
     no orphan processes
```

## Why files instead of chat

- CLI runs are **stateless** (`-p` spawns a fresh session every time). Files are the only memory.
- Files make the human gate real: an APPROVED.md with a checksum and a typed token is an auditable artifact; "the AI said the user agreed" is not.
- Files make monitoring trivial: poll `PROGRESS.md` from anywhere — the desktop assistant, another terminal, a script.

## Context management: the staged-checkpoint discipline

Unattended runs eventually hit auto-compact, which eats the old turns the goal evaluator reads for evidence. BuddyBridge's countermeasure is in the PLAN template: every 5 acceptance items, the agent **archives the stage verbatim to STAGE-{N}.md** and **self-reports its state into the conversation** — so the full version lives on disk and the latest evidence lives at the transcript tail, where compression can't reach it. Reloads are index-only (never paste whole files back), preserving prefix-cache hit rates.

## The three runs of a large project

1. **Research** (Engine A): dispatch `RESEARCH-BRIEF.md` → `REPORT.md` with citations lands on disk. Prefer the official `/deep-research` built-in when it fits.
2. **Plan**: convert findings into `PLAN.md` acceptance items → cross-review (A1) → final review (A2) → **human approval** (APPROVED.md).
3. **Execute** (Engine B): dispatch the approved `PLAN.md` → unattended goal loop self-reports into `PROGRESS.md` → verify.

Small tasks skip stages: a simple checklist can go straight to Engine B (still gated); a quick sanity check can be a single conversation.

## What "dispatch" actually is

Inside a WorkBuddy conversation, you say *"dispatch this plan to the CLI"* — the assistant runs the pre-flight checks and **hands you the exact command** (absolute paths, idempotency guard, turn caps, model routing all filled in). You paste it into your own terminal and walk away; the assistant monitors the artifact files and reports progress. See [dispatch.md](dispatch.md) for why v1 rides on your own terminal rather than in-session spawning (a documented, layered Windows host-mode issue — v1.1 territory).
