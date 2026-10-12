# CLAUDE.md — HueBar

HueBar is a Mac menu bar app that turns Hue lights and scenes on and off, grouped by room, with nothing else in the way.

@docs/conventions.md

---

## The documents

| Artifact | Role | Path |
|---|---|---|
| **CLAUDE.md** | standing rules. Loaded every session. | root |
| **conventions.md** | the grammar: axes, IDs, merge discipline. Vendored + pinned. | `docs/conventions.md` |
| **SPEC.md** | the contract. Vision sentence, `FR`/`NFR`. **Immutable.** | `docs/specs/SPEC.md` |
| **Register** | `D` · `RR` · `O` · `H` · `M` | `docs/plans/00-register.md` |
| **Plan / Review** | per unit, at the gate / after | `docs/plans/F<N>.md` · `docs/reviews/F<N>.md` |

Where the spec and the register conflict, **the register wins**.

---

## Non-negotiable

- **Scope is `SPEC.md` FR1–FR7.** Brightness, color, event stream, Keychain, mDNS, shortcuts are future milestones. Do not build or stub them; open a `D<n>` and stop.
- **`HueCore` never imports AppKit.** Everything that talks to the bridge stays testable without a UI.
- **No third-party dependencies** without a ratified `D<n>`.
- **The bridge app key never enters the tree.** It lives in UserDefaults on the user's Mac (D2). Tests read it from `HUE_APP_KEY` only.
- **The agent never edits `SPEC.md`.** Propose deltas; the owner ratifies.

---

## Authorization

1. Specs and plans are context, not work orders.
2. Work begins only when Marty gives explicit instruction in the current session.
3. **Gates need a verbal yes.** Every feature and milestone boundary is a gate.
4. **Defect fixes proceed without a gate.** Everything else waits.

---

## Learning level: 5% (proposed, not yet locked — `O2`)

The agent authors everything; Marty reviews every PR and does not write Swift. **Every PR description is written for a reviewer who can read code but not Swift**: what changed, why, what to test, what could break. The dial is the `owner` field on every task.

---

## Workflow

1. **Gate → plan.** Re-read `SPEC.md` and the register, write `docs/plans/F<N>.md`, wait for the yes.
2. **Build.** Branch `F<N>/<slug>`, conventional commits with the structural ID in scope, never a register ID.
3. **Adversarial review** with `.claude/agents/adversarial-reviewer.md` at the end of every feature and the start of every session.
4. **Verify with evidence.** `swift test` output in the PR, plus the live check: `HUE_BRIDGE_HOST=<ip> swift test`. Assertions are not evidence.
5. **PR.** Rebase-and-merge only.

**Read before you overwrite.** Never use shell redirection to get past the Write tool's guard.

---

## Hooks

| Hook | Surface | Status |
|---|---|---|
| `swift test` | CI | not wired (C1) |
| No register ID in a commit, branch, or PR title | commit-msg | not wired (C1) |
| Secret scan | pre-commit + CI | not wired (C1) |

---

## Stack

Swift 5.9 language mode on Swift 6.4 toolchain · SwiftPM · AppKit · macOS 14+ · no lint yet. Build the bundle with `scripts/build-app.sh`.

-----
2026-10-12

#AI/Claude
