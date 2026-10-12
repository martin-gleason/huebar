#!/bin/zsh
# Build a release binary and wrap it in a proper .app bundle (ad-hoc signed).
#   scripts/build-app.sh            -> build/HueBar.app
#   scripts/build-app.sh --install  -> also copies to ~/Applications/HueBar.app
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/HueBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HueBar "$APP/Contents/MacOS/HueBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  ditto "$APP" ~/Applications/HueBar.app
  echo "Installed ~/Applications/HueBar.app"
fi
