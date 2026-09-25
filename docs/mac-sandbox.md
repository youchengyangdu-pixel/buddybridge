# Isolation Safety Model: macOS Sandbox, Windows Options, and What Bypass Actually Means

## The honest baseline first

`-y` (bypassPermissions) skips general approvals, but HIGH/CRITICAL dangerous commands are still blocked in headless mode (surfacing as refusals — see [dispatch.md](dispatch.md)). The `deny` baseline from the install cards is the one guardrail that outranks everything, bypass included. Sandbox layers go **on top of that**, not instead of it.

## macOS: the Bash sandbox

CodeBuddy's Bash sandbox is **only available on macOS/Linux**. On macOS you can stack a real OS-level sandbox underneath headless runs — the security model Codex popularized: **sandbox instead of approval**.

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "network": { "allowLocalBinding": true }
  }
}
```

| Key | Effect | Honest notes |
|---|---|---|
| `enabled` | Bash commands run isolated from the filesystem/network at the OS level | Official docs disagree with themselves on the default (one place says `true`, another `false`) — **write it explicitly, never rely on the default** |
| `autoAllowBashIfSandboxed` | Commands inside the sandbox are auto-approved | Its auto-approval mechanism is premised on **acceptEdits mode**; under `-y` (bypass) the real benefit of the sandbox is the filesystem/network isolation itself, not this flag |
| `allowUnsandboxedCommands: false` | **The hard boundary.** Default is permissive: a command that fails due to sandbox limits gets retried *outside* the sandbox via `dangerouslyDisableSandbox` | Without this flag, "the sandbox holds" is a comforting story — a prompt-injected agent can move its own commands outside the cage. Setting `false` closes the escape hatch; sandbox-breaking commands then fail instead of escaping |
| `network.allowLocalBinding` | Allow binding localhost (dev servers) | This **loosens** the official default (`false`) — enable only if the task needs a local server |

The result: an unattended agent works freely inside the box; commands that need to leave the box fail loudly instead of escaping quietly. Sandbox shrinks the blast radius; the `deny` baseline still governs; bypass reduces interruptions. **"Sandbox + bypass" is layered risk reduction, not "double insurance" in the absolute sense.**

## All platforms: the isolation options matrix

Windows is **not** "no isolation, deal with it":

| Isolation option | macOS/Linux | Windows |
|---|---|---|
| Bash sandbox (`sandbox.enabled`) | ✅ OS-level | ❌ not available |
| `--sandbox container` (Docker/Podman, Beta) | ✅ | ✅ |
| `--sandbox <E2B URL>` (cloud sandbox) | ✅ | ✅ |
| `--worktree <name>` (isolated git worktree) | ✅ | ✅ |
| `deny` baseline in settings | ✅ (always on, from install card) | ✅ |

On Windows, if you want stronger isolation than deny-rules + dangerous-command checks: run dispatches with `--sandbox container` (needs Docker) or inside a `--worktree`. On any platform, a disposable VM/container plus `CODEBUDDY_IS_SANDBOX=1` + `-y` is the official full-pass recipe — flagged high-risk for good reason; keep it away from machines holding production credentials.

## Escape hatches (deliberate, documented)

- `excludedCommands`: commands that must run outside the sandbox (e.g. `docker`); note the official docs say WorkBuddy Desktop ignores this setting. Consider adding `git push` if you *intentionally* allow pushes — the deny baseline blocks it by default.
- Sandbox config files themselves are write-protected from inside the sandbox — an agent can't loosen its own cage mid-run.
- Filesystem and network boundaries are additionally shaped by `Read`/`Edit`/`WebFetch` permission rules — sandbox and permission rules **intersect** (both must allow).

## Practical notes for unattended runs

- If a dispatched task needs paths outside the project (package caches, global npm), either widen the sandbox's write allowances in config or expect those commands to fail — on macOS they fail *safely*, which is the point.
- Engine A's workflow sub-agents inherit the sandbox too.
- Either way, the `PROGRESS.md` checksummed ledger is your audit trail — that's the BuddyBridge trust model on every platform.
