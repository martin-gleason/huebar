# Local conventions — HueBar

## Harness

| Purpose | Command |
|---|---|
| Build | `swift build` |
| Offline tests | `swift test` |
| Live tests (bridge on LAN) | `HUE_BRIDGE_HOST=<ip> swift test` · add `HUE_APP_KEY=<key>` to read the home |
| App bundle | `scripts/build-app.sh` (add `--install` for `~/Applications`) |

Stack: Swift 5.9 language mode, SwiftPM, AppKit, macOS 14+. No lint configured yet.
