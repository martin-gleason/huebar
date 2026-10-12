# HueBar — SPEC

Created: 2026-10-12 11:06 -05:00 · Edited: 2026-10-12 11:30 -05:00

HueBar is a Mac menu bar app that turns Hue lights and scenes on and off, grouped by room, with nothing else in the way.

> **Vision sentence status: proposed by the agent on 2026-10-12, not yet ratified by the owner (`O1`).**

## Functional requirements

| ID | Requirement |
|---|---|
| FR1 | Lights are listed grouped by Hue room, then zone. Lights in no room appear under "Other Lights". |
| FR2 | Each light can be toggled on/off from the menu; its current state is shown as a checkmark. |
| FR3 | Each room offers "All On" and "All Off". |
| FR4 | Each room lists its scenes; selecting one recalls it. |
| FR5 | "All Lights Off" is available at the top level. |
| FR6 | First run: find the bridge (cloud lookup or typed address), pair via the link button, and keep the credential across launches. |
| FR7 | The menu reflects bridge state when opened and re-syncs after every action. |

## Non-functional requirements

| ID | Requirement |
|---|---|
| NFR1 | Resident memory under 30 MB at idle. AppKit only; no SwiftUI; no polling timers. |
| NFR2 | A click updates the menu immediately and the bridge request leaves within 100 ms (optimistic UI). |
| NFR3 | No third-party dependencies. |
| NFR4 | TLS to the bridge is pinned on first use to the bridge certificate's SHA-256. |
| NFR5 | macOS 14 or later, Apple silicon and Intel. |

## Hook intentions

- Every FR has a test or a named manual check, recorded in the feature plan.
- `swift test` is the harness; the offline tests must pass on every change.

## Out of scope for MVP (future milestones, enter via `D<n>`)

Brightness and color · live updates via the bridge event stream · mDNS discovery · Keychain storage · keyboard shortcuts · multiple bridges.
