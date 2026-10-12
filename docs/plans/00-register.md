# Register — HueBar

Append-only. Decisions are immutable once ratified; supersede, never edit.

## D — Decisions

| ID | Status | Date | Decision |
|---|---|---|---|
| D1 | proposed | 2026-10-12 | Use the Hue CLIP **v2** API (`/clip/v2`) rather than v1. Rooms, zones, scenes and grouped lights are first-class, which is what the menu is built from. |
| D2 | proposed | 2026-10-12 | Store bridge address, app key and certificate fingerprint in **UserDefaults** for MVP. Keychain storage is the first growth item; the app key is a bridge credential. |
| D3 | proposed | 2026-10-12 | Trust the bridge's TLS certificate **on first use** and pin its SHA-256 thereafter. Changing the bridge address resets the pin. |
| D4 | proposed | 2026-10-12 | Discovery via Signify's cloud lookup plus a manual address field. mDNS is deferred (it also trips macOS Local Network permission more often). |
| D5 | proposed | 2026-10-12 | Project layout: `HueCore` library (no AppKit, fully testable) + thin `HueBar` AppKit executable + `scripts/build-app.sh` to wrap it as a `.app`. No Xcode project. |

## RR — Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| RR1 | macOS Local Network permission denies the app when a second user account is logged in via fast user switching (observed 2026-10-12 with Hue Menu on this Mac). | High on this Mac | App cannot reach the bridge; looks like "bridge not found" | Log the other account out; README documents the symptom and the log query that confirms it. | human |
| RR2 | Cloud discovery needs the bridge to have internet access. | Low | Find Bridge… fails | Manual address entry is always offered. | agent |

## O — Owner items

| ID | Priority | Item | Status |
|---|---|---|---|
| O1 | P1 | Ratify or rewrite the vision sentence in `docs/specs/SPEC.md`. | open |
| O2 | P1 | Lock the learning level. Agent proposes **5%** (Swift is not in the owner's language set). | open |
| O3 | P0 | Press the bridge link button and complete pairing in the app; then run `HUE_BRIDGE_HOST=… HUE_APP_KEY=… swift test` to close FR1–FR7 live checks. | open |
| O4 | P2 | Ratify D1–D5. | open |

## H — Hooks

| ID | Invariant | Mechanism | Owning task | Status |
|---|---|---|---|---|
| H1 | Offline tests pass on every change | `swift test` in CI | C1 | not wired |
| H2 | Every FR has a test or named manual check | review checklist in `docs/plans/F1.md` | F1 | manual |

## M — Mutations

| ID | Break it by… | Caught by |
|---|---|---|
| M1 | Grouping lights by light id instead of device id for rooms | `SnapshotTests.testLightsGroupByRoomThenZoneThenUnassigned` |
| M2 | Accepting any certificate once a pin exists | `BridgeIntegrationTests.testWrongFingerprintIsRejected` |
| M3 | Treating error type 101 as a generic failure | `BridgeIntegrationTests.testPairingWithoutLinkButtonReportsIt` |
