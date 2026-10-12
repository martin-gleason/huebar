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
| D6 | proposed | 2026-10-12 | **Supersedes D2 if ratified.** The paired credential (host + app key + bridge id + certificate fingerprint) is one Keychain item (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Only the un-paired bridge address stays in UserDefaults. Source: red-team finding S1. |
| D7 | proposed | 2026-10-12 | **Extends D3.** The bridge certificate must chain to Signify's embedded `root-bridge` CA (system roots ignored) and carry a bridge id as CN; the id and leaf fingerprint are then pinned. Trust-on-first-use alone is no longer sufficient. Source: finding S2. |
| D8 | proposed | 2026-10-12 | The app bundle is signed with App Sandbox (network client only) and hardened runtime. Ad-hoc identity until a Developer ID exists. Source: finding S7. |

## RR — Risks

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| RR1 | macOS Local Network permission denies the app when a second user account is logged in via fast user switching (observed 2026-10-12 with Hue Menu on this Mac). | High on this Mac | App cannot reach the bridge; looks like "bridge not found" | Log the other account out; README documents the symptom and the log query that confirms it. | human |
| RR2 | Cloud discovery needs the bridge to have internet access. | Low | Find Bridge… fails | Manual address entry is always offered. | agent |
| RR3 | Ad-hoc code signature changes on every build, so the Keychain ACL prompts after each rebuild of a dev build. | Certain for dev builds | Annoying prompt; no data exposure | Sign with a Developer ID for releases. | human |
| RR4 | Anyone on the LAN who presses the bridge's link button can pair their own client. Inherent to Hue; not addressable by this app. | Low | Full light control by a LAN attacker | Physical control of the bridge. Documented. | human |
| RR5 | Bridges on firmware older than 1.24 present self-signed certificates and will now be refused. | Low | App unusable with very old bridges | Documented; user updates bridge firmware. | human |

## O — Owner items

| ID | Priority | Item | Status |
|---|---|---|---|
| O1 | P1 | Ratify or rewrite the vision sentence in `docs/specs/SPEC.md`. | open |
| O2 | P1 | Lock the learning level. Agent proposes **5%** (Swift is not in the owner's language set). | open |
| O3 | P0 | Press the bridge link button and complete pairing in the app; then run `HUE_BRIDGE_HOST=… HUE_APP_KEY=… swift test` to close FR1–FR7 live checks. | open |
| O4 | P2 | Ratify D1–D5. | open |
| O5 | P1 | Ratify D6–D8 (red-team hardening). | open |
| O6 | P2 | Decide repo visibility: it is private now; flip with `gh repo edit martin-gleason/huebar --visibility public --accept-visibility-change-consequences` once O5 is ratified. | open |

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
| M4 | Interpolating the host into the URL without validation | `HostValidationTests.testRejectsURLInjectionVariants`, `testInvalidHostNeverTouchesTheNetwork` |
| M5 | Interpolating bridge-supplied ids into the path without validation | `ResourceIDTests.testTraversalAndQueryIDsAreRefusedBeforeAnyRequest` |
| M6 | Accepting any certificate on first use | `BridgeTrustTests.testSelfSignedImpostorWithBridgeLikeCNIsRejected`, `testHueRootPresentedAsLeafIsRejected` |
| M7 | Sending the key to a bridge whose id differs from the pinned one | `BridgeIntegrationTests.testWrongBridgeIDIsRejected` (live) |
| M8 | Reading the whole response into memory without a cap | `HostileResponseTests.testOversizedBodyIsRejectedByContentLength` |
| M9 | Trusting discovery results as addresses | `DiscoveryTests.testOnlyPrivateIPLiteralsWithBridgeIDsSurvive` |
| M10 | Putting bridge-supplied text into the menu unfiltered | `HostileResponseTests.testNamesFromBridgeAreSanitized`, `testLongErrorTextIsBounded` |
| M11 | Storing the app key in UserDefaults | `KeychainTests.testCredentialRoundTripsThroughKeychainNotDefaults` |
| M12 | Removing the task-level TLS challenge handler (streaming API then bypasses our trust code) | `BridgeIntegrationTests.testPairingWithoutLinkButtonReportsIt` (live only) |
