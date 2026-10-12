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
# App icon: Resources/AppIcon.icon is an Icon Composer package (layered, Liquid Glass on
# macOS 26+). actool emits Assets.car for the system renderer and a flat .icns fallback.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon --include-all-app-icons \
  --output-partial-info-plist build/icon-partial.plist --output-format human-readable-text >/dev/null
# App Sandbox + hardened runtime. Ad-hoc identity: replace "-" with a Developer ID to notarize.
codesign --force --options runtime --entitlements Resources/HueBar.entitlements --sign - "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  ditto "$APP" ~/Applications/HueBar.app
  echo "Installed ~/Applications/HueBar.app"
fi
