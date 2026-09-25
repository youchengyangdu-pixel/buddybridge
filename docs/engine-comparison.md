# Engine Comparison: Workflows vs Sub-agents vs Skills vs Agent Teams

CodeBuddy offers four multi-step primitives. The official docs frame the difference as **"who holds the plan"** — and that framing decides which one BuddyBridge dispatches to.

|  | Sub-agents | Skills | Agent Teams | Workflows (Engine A) |
|---|---|---|---|---|
| **Essence** | Workers CodeBuddy delegates to | Instructions CodeBuddy follows | A leader coordinating peer sessions | A script the runtime executes |
| **Who decides the next step** | CodeBuddy, turn by turn | CodeBuddy, per prompt | The leader agent, turn by turn | **The script** |
| **Where intermediate results live** | CodeBuddy's context window | CodeBuddy's context window | Shared task list | **Script variables** |
| **What's repeatable** | The worker definition | The instruction itself | The team definition | **The orchestration itself** |
| **Scale** | A few delegations per turn | Same as sub-agents | A few long-lived peers | Dozens–hundreds of agents per run |
| **Interruption** | Start a new turn | Start a new turn | Teammates keep running | Resumable **within the same session** |

Source: official `workflows.md` comparison table, lightly edited.

## Why BuddyBridge maps engines the way it does

- **Engine A = Workflows** for research/review: parallel fan-out + adversarial peer-critique are exactly what "many brains critiquing each other" needs, and script-held plans keep intermediate results out of the orchestrator's context. The fallback (multi-`-p` + `--model`) is the same topology built from sub-agent-style single runs — guaranteed vendor-heterogeneous routing.
- **Engine B = Goal loop** (not in the table — it's a session-level construct, not a delegation primitive): the plan lives in the *evaluator's* turn-by-turn judgment plus the on-disk PLAN/PROGRESS ledger. That's what makes it **resumable across process restarts** — the property Workflows explicitly lack ("process exit = run gone"). Checklist execution values resumability over parallelism, hence Engine B.
- **Skills = how the bridge itself is taught**: the buddybridge SKILL.md is an instruction artifact for the desktop assistant, not an execution engine.
- **Agent Teams**: peer coordination with a leader — v2 roadmap territory (multi-task orchestration panel), not needed for the single-task dispatch loop of v1.

## The one-line version

> Sub-agents/Skills/Teams put the plan in someone's *head* (and context window); Workflows put it in *code*; the Goal loop puts it in a *ledger*. BuddyBridge picks per task: critique-parallelism → code; crash-resumable grinding → ledger.
