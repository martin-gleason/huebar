# HueBar

A barebones Mac menu bar app for Philips Hue: lights and scenes, grouped by room, on and off. Nothing else.

```
💡
├─ Office            ▸  All On · All Off · ── Scenes ── Relax · Bright · ── Lights ── ✓ Lamp · Ceiling
├─ Living Room       ▸
├─ ── Other Lights ──
│  ✓ Hallway
├─ All Lights Off
├─ Refresh                 ⌘R
├─ Bridge: 192.168.0.189
├─ Set Bridge Address…
├─ Pair Again…
└─ Quit HueBar             ⌘Q
```

## Build and install

```
scripts/build-app.sh --install     # → ~/Applications/HueBar.app
open ~/Applications/HueBar.app
```

Requires Xcode command line tools and macOS 14 or later. No dependencies.

## First run

1. Click the bulb, choose **Find Bridge…** (uses the Hue cloud lookup) or **Set Bridge Address…** and type the bridge IP.
2. Press the round button on the bridge, then click **Pair**.
3. macOS will ask to allow HueBar on the local network. Allow it.

The bridge address, app key and the bridge certificate's SHA-256 are kept in UserDefaults (`defaults read dev.marty.HueBar`). Setting a different address clears all three.

## Layout

| Path | What |
|---|---|
| `Sources/HueCore/` | Talks to the bridge. No AppKit, so it is tested headless. `HueClient` (CLIP v2 over pinned TLS, pairing), `Models` (the handful of fields used), `Snapshot` (rooms → lights + scenes), `Discovery`. |
| `Sources/HueBar/` | The menu bar app. `AppDelegate` builds menus from a `HueSnapshot` and forwards clicks; `Settings` wraps UserDefaults. |
| `Tests/HueCoreTests/` | Offline grouping tests, plus live tests that run only when `HUE_BRIDGE_HOST` is set. |
| `scripts/build-app.sh` | Release build wrapped as a signed `.app` with the Info.plist in `Resources/`. |
| `docs/` | Spec, register, plans. See `CLAUDE.md`. |

## How it stays small and quick

- AppKit `NSStatusItem` + `NSMenu`; no SwiftUI, no windows, no timers.
- The menu refreshes when opened. Cached state shows instantly; checkmarks update in place when the bridge answers.
- Clicks are optimistic: the menu changes immediately, the request goes out, and a re-sync follows 0.7 s later.
- One ephemeral `URLSession`, no cache, 6 s timeouts. Five resources are fetched concurrently per refresh.

## Room to grow

Each is a contained change:

- **Brightness / color**: add `dimming`/`color` to `Light` in `Models.swift`, a `put` in `HueClient`, and a slider view as a menu item.
- **Live updates**: subscribe to `/eventstream/clip/v2` in `HueClient` and apply events to the snapshot instead of re-fetching.
- **Keychain**: replace the `appKey` accessor in `Settings.swift`.
- **mDNS discovery**: add an `NWBrowser` for `_hue._tcp` to `Discovery.swift` (`NSBonjourServices` is already declared).
- **Shortcuts**: assign `keyEquivalent`s in `roomItem`/`lightItem`.

## Tests

```
swift test                                               # offline
HUE_BRIDGE_HOST=192.168.0.189 swift test                 # live: TLS pin + pairing endpoint
HUE_BRIDGE_HOST=… HUE_APP_KEY=… swift test               # live: reads rooms, lights, scenes
```

## If the bridge is "not found"

If curl can reach the bridge but the app cannot, check macOS Local Network permission. A second user account left logged in via fast user switching can override your allow with its deny. This prints the denial if that is happening:

```
/usr/bin/log show --last 5m --predicate 'process == "HueBar" AND eventMessage CONTAINS "Local network prohibited"' | grep -c prohibited
```
