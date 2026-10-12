# Security red-team review — HueBar 0.1 → 0.2

Created: 2026-10-12 11:17 -05:00 · Edited: 2026-10-12 11:30 -05:00

**Date:** 2026-10-12 · **Reviewer:** agent, acting as an adversary with the public source · **Scope:** everything in the repository at commit `6dca2e6` (the first commit) · **Outcome:** 7 findings, 6 fixed in C2, 1 inherent to the Hue platform and documented. **Repository stays private until the owner ratifies D6–D8 (`O5`, `O6`).**

## Threat model

HueBar is a trusted local client for a LAN device. The attacker positions considered:

| Position | Capability | What they want |
|---|---|---|
| **A. Same LAN** | ARP/DNS spoofing, answering on the bridge's IP, racing discovery | Harvest the app key; impersonate the bridge; make the app talk to them |
| **B. Hostile bridge** | A compromised or counterfeit bridge returning arbitrary JSON | Crash or exhaust the app; inject into the UI; steer requests elsewhere |
| **C. Internet** | Control or spoof the Signify discovery response | Point the app at an attacker host |
| **D. Local process** | Any non-root process running as the user | Read the app key from disk; rewrite settings to redirect the app |
| **E. Supply chain / build** | Clone the repo, run the scripts | Nothing sensitive present; checked anyway |

Out of scope: root on the Mac, physical access to the bridge, Hue cloud account security.

## Findings

Severity: **High** = credential theft or silent control of lights by an attacker; **Medium** = app made to misbehave by hostile data; **Low** = hygiene.

### S1 · High · App key stored in plaintext UserDefaults (position D)

`Settings.swift` wrote `bridgeAppKey` to `~/Library/Preferences/dev.marty.HueBar.plist`. Any process running as the user could run `defaults read dev.marty.HueBar bridgeAppKey` and control the lights indefinitely, from anywhere on the LAN, with no prompt. The same file held the TOFU fingerprint and the host, so a local process could also rewrite host + fingerprint and the app would send the key to the new host on next launch.

**Fix (D6):** the credential is one Keychain item (`BridgeCredential`: host, app key, bridge id, fingerprint), `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Only the un-paired address stays in UserDefaults, and `makeClient` ignores a credential whose host differs from it. A one-time migration moves pre-0.2 keys out of defaults and deletes them.
**Test:** `KeychainTests.testCredentialRoundTripsThroughKeychainNotDefaults`.
**Residual:** ad-hoc signed dev builds prompt once per rebuild (RR3). A Developer ID signature removes that.

### S2 · High · Trust-on-first-use lets a LAN attacker become the bridge (position A)

`HueClient` accepted whatever certificate it saw first and pinned it. An attacker answering on the bridge's IP during first run (ARP spoof, or simply before the user has paired) would be pinned as "the bridge", receive the app key on every request, and could proxy to the real bridge so nothing looked wrong. A certificate rotation on the real bridge was indistinguishable from an attack.

**Fix (D7):** `BridgeTrust` evaluates the chain strictly against Signify's embedded `root-bridge` CA (`SecTrustSetAnchorCertificatesOnly`, system roots ignored), requires a chain of at least two certificates, and requires the leaf CN to be a 16-hex-digit bridge id. The id and leaf fingerprint are then pinned; a mismatch on either is refused before any request body or header is sent. Verified offline with an impostor self-signed certificate whose CN mimics a bridge id, and live against the owner's bridge (id `ecb5fafffe117ed9`).
**Tests:** `BridgeTrustTests.*`, `BridgeIntegrationTests.testPairingWithoutLinkButtonReportsIt`, `testWrongBridgeIDIsRejected`, `testWrongFingerprintIsRejected`.
**Residual:** bridges on firmware < 1.24 use self-signed certificates and are now refused (RR5).

### S3 · High · Host string interpolated into the URL unvalidated (positions C, D)

`URL(string: "https://\(host)\(path)")` with `host` from the address dialog or from discovery. A value such as `evil.example/x?` or `192.168.0.189@evil.example` produced a syntactically valid URL to a different origin, and every request to it carried `hue-application-key`. Variations tried: path, query, fragment, userinfo, port, CR/LF, NUL, embedded whitespace, backslash, unicode, overlong labels, bare IPv6.

**Fix:** `Validation.host` accepts only an IPv4 literal, a bracketed IPv6 literal, or an RFC 1123 hostname, and is applied both in the dialog and on every request. An invalid host sends nothing.
**Tests:** `HostValidationTests.testRejectsURLInjectionVariants` (26 variants), `testInvalidHostNeverTouchesTheNetwork`.

### S4 · Medium · Discovery result and bridge-supplied ids trusted as-is (positions B, C)

`Discovery.cloud()` returned `internalipaddress` straight from the internet and the app set it as the host; a spoofed or poisoned response could name any host. Resource ids from bridge JSON were interpolated into request paths, so a hostile bridge could make the app issue `PUT /clip/v2/resource/light/../../api/0/config`-style requests against itself.

**Fix:** `Discovery.validate` keeps only private IPv4/IPv6 literals with bridge-shaped ids and caps the response at 64 KB. `Validation.resourceID` restricts ids to `[A-Za-z0-9_-]{1,64}` and is applied before any URL is built.
**Tests:** `DiscoveryTests.*`, `ResourceIDTests.*`.

### S5 · Medium · Unbounded response bodies (position B)

`URLSession.data(for:)` buffered whatever the server sent. A hostile bridge returning gigabytes would exhaust memory in a 14 MB app. Found by review; the stub test confirms the cap.

**Fix:** responses stream through `bytes(for:)` into a buffer capped at 4 MB (`HueClient.maxResponseBytes`), with an early reject on `Content-Length`.
**Test:** `HostileResponseTests.testOversizedBodyIsRejectedByContentLength`.
**Note:** switching to the streaming API silently stopped routing TLS challenges to the session-level delegate; the system's default trust evaluation then rejected the real bridge. Only the live test caught it. The client now implements the task-level challenge handler as well (see "Lessons").

### S6 · Low · Bridge-supplied text rendered unfiltered in the menu (position B)

Light, room and scene names and API error strings went straight into `NSMenuItem` titles: control characters, line breaks, thousands of characters. Not exploitable for code execution, but a hostile bridge could make the menu unusable or misleading.

**Fix:** `Validation.displayName` strips control characters and newlines and bounds length (60 for names, 120 for errors); never empty.
**Tests:** `HostileResponseTests.testNamesFromBridgeAreSanitized`, `testLongErrorTextIsBounded`.

### S7 · Low · No sandbox, no hardened runtime (defense in depth)

The bundle ran unconfined. A bug in JSON handling or a future dependency would have had the user's whole home directory.

**Fix (D8):** `build-app.sh` signs with `Resources/HueBar.entitlements` (App Sandbox, outbound network only) and `--options runtime`. Verified: `codesign -d --entitlements` shows both keys; the app launches, creates its container, and reads the migrated credential.
**Residual:** ad-hoc identity. Gatekeeper will warn on other Macs until the app is signed with a Developer ID and notarized.

### S8 · Inherent · Link-button pairing (position A)

Anyone on the LAN who can press the bridge's button can pair their own client. This is the Hue trust model, not an app defect; it cannot be mitigated client-side. Recorded as RR4.

## Checked and found clean

- No secrets in the tree: no app keys, no certificates other than Signify's public root and a throwaway self-signed test fixture (its private key was discarded at generation).
- The app key is sent only as a header, only to `/clip/v2/…` on the pinned bridge, never in a URL or log line (`CredentialOnTheWireTests`). Pairing sends no key.
- No third-party dependencies; build script has no network step beyond `swift build`.
- Cookies disabled, URL cache disabled, TLS ≥ 1.2, ATS relaxed only for local networking.
- Optimistic UI cannot be used to desync state: every action is followed by a re-fetch.
- `pair()` rejects an empty username.

## Test inventory

| Suite | Tests | Runs |
|---|---|---|
| `SnapshotTests` | 3 | always |
| `HostValidationTests` | 3 | always |
| `ResourceIDTests` | 2 | always |
| `CredentialOnTheWireTests` | 3 | always |
| `HostileResponseTests` | 4 | always |
| `DiscoveryTests` | 2 | always |
| `BridgeTrustTests` | 4 | always |
| `KeychainTests` | 1 | always (skips if the Keychain is unavailable) |
| `BridgeIntegrationTests` | 4 | `HUE_BRIDGE_HOST=<ip> [HUE_BRIDGE_ID=<id>] [HUE_APP_KEY=<key>] swift test` |

Evidence, 2026-10-12: `swift test` → 26 tests, 0 failures, 4 skipped (the live ones). `HUE_BRIDGE_HOST=192.168.0.189 HUE_BRIDGE_ID=ecb5fafffe117ed9 swift test --filter BridgeIntegrationTests` → 4 tests, 0 failures, 1 skipped (`testSnapshotWithKey`, no `HUE_APP_KEY` supplied to the test run).

## What the tests do not prove

- S1–S4 were found by reading the first commit; the tests were written against the fixed code and pin the fix. They were not run against the original code (the original `HueClient` had no transport hook), so "the old code failed these tests" is by inspection, not by execution.
- A live man-in-the-middle was not staged. The impostor-certificate test exercises the same evaluation path the delegate uses, and the live tests prove that path runs on real connections.
- Sandbox + Keychain + Local Network permission interaction was verified only on the owner's Mac.

## Lessons

- **A transport change can silently change trust handling.** `data(for:)` → `bytes(for:)` moved server-trust challenges from the session-level delegate to the task-level one. Nothing offline could see it. Any change to `HueClient` must be followed by the live suite (recorded as mutation M12).
- Validation at the boundary (`Validation.swift`) is cheaper than validation at use: three call sites, one set of rules, one test file.

## Open items for the owner

| Item | Why |
|---|---|
| Ratify D6, D7, D8 (`O5`) | They change where the credential lives and what the app will connect to. |
| Flip the repo to public (`O6`) | After O5. One command, in the register. |
| Developer ID + notarization | Removes the per-build Keychain prompt and Gatekeeper warning. |
