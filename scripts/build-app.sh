#!/bin/bash
#
# Builds MikroTikDashboard.app, including the WidgetKit extension, using only
# the Command Line Tools toolchain.
#
# Xcode packages an .appex by convention, not by magic: an app extension is a
# plain Mach-O executable inside a bundle whose Info.plist declares an
# NSExtensionPointIdentifier. swiftc can produce that, so a full Xcode install
# is not required. MikroTikDashboard.xcodeproj describes the same two targets
# for anyone who does have Xcode.
#
# Usage: scripts/build-app.sh [debug|release]

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MikroTikDashboard"
WIDGET_NAME="MikroTikWidget"
APP_BUNDLE_ID="io.github.macosmikrotikwidget"
WIDGET_BUNDLE_ID="io.github.macosmikrotikwidget.widget"
DEPLOYMENT_TARGET="14.0"

BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/derived"
BUNDLE="$BUILD_DIR/$APP_NAME.app"
APPEX="$BUNDLE/Contents/PlugIns/$WIDGET_NAME.appex"

ARCH="$(uname -m)"
TARGET_TRIPLE="$ARCH-apple-macos$DEPLOYMENT_TARGET"
SDK_PATH="$(xcrun --show-sdk-path)"

if [[ "$CONFIGURATION" == "debug" ]]; then
    SWIFT_OPT=(-Onone)
    SWIFT_CONDITIONS=(-D DEBUG)
else
    SWIFT_OPT=(-O)
    # bash 3.2 (the macOS system bash) treats an empty array as unset under
    # `set -u`, so this always carries at least one flag.
    SWIFT_CONDITIONS=(-D RELEASE)
fi

cd "$ROOT"

# ---------------------------------------------------------------------------
# 1. Shared framework code
#
# The widget is a separate process and cannot link the app, so MikroTikKit is
# compiled once into a static archive that both binaries link against. The
# emitted .swiftmodule is what makes `import MikroTikKit` resolve.
# ---------------------------------------------------------------------------
echo "==> Building MikroTikKit ($CONFIGURATION)"
mkdir -p "$DERIVED"
swiftc \
    -module-name MikroTikKit \
    -parse-as-library \
    -emit-module -emit-module-path "$DERIVED/MikroTikKit.swiftmodule" \
    -emit-library -static -o "$DERIVED/libMikroTikKit.a" \
    -target "$TARGET_TRIPLE" -sdk "$SDK_PATH" \
    "${SWIFT_OPT[@]}" "${SWIFT_CONDITIONS[@]}" \
    "$ROOT"/Sources/MikroTikKit/*.swift

# ---------------------------------------------------------------------------
# 2. Application binary
# ---------------------------------------------------------------------------
echo "==> Building $APP_NAME ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

BINARY="$(swift build -c "$CONFIGURATION" --product "$APP_NAME" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
    echo "error: built binary not found at $BINARY" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. Widget extension binary
#
# MIKROTIK_WIDGET_EXTENSION switches on the @main WidgetBundle entry point,
# which stays out of the SwiftPM library build so that target remains a library.
# ---------------------------------------------------------------------------
echo "==> Building $WIDGET_NAME extension"
swiftc \
    -module-name "${WIDGET_NAME}Extension" \
    -o "$DERIVED/$WIDGET_NAME" \
    -target "$TARGET_TRIPLE" -sdk "$SDK_PATH" \
    "${SWIFT_OPT[@]}" "${SWIFT_CONDITIONS[@]}" \
    -D MIKROTIK_WIDGET_EXTENSION \
    -I "$DERIVED" -L "$DERIVED" -lMikroTikKit \
    -framework WidgetKit -framework SwiftUI \
    "$ROOT"/Sources/MikroTikWidget/*.swift

# ---------------------------------------------------------------------------
# 4. Bundle assembly
# ---------------------------------------------------------------------------
echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/App/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

cp "$DERIVED/$WIDGET_NAME" "$APPEX/Contents/MacOS/$WIDGET_NAME"
cp "$ROOT/Widget/Info.plist" "$APPEX/Contents/Info.plist"
printf 'XPC!????' > "$APPEX/Contents/PkgInfo"

# The checked-in plist uses the Xcode build-setting placeholders; substitute
# them here so both build paths produce an identical bundle.
plutil -replace CFBundleExecutable -string "$WIDGET_NAME" "$APPEX/Contents/Info.plist"
plutil -replace CFBundleName -string "$WIDGET_NAME" "$APPEX/Contents/Info.plist"

# Fails loudly if either plist was edited into an invalid state.
plutil -lint "$BUNDLE/Contents/Info.plist" > /dev/null
plutil -lint "$APPEX/Contents/Info.plist" > /dev/null

# ---------------------------------------------------------------------------
# 5. Signing
#
# Nested code signs inside-out: the extension first, then the app containing it.
#
# The entitlements are used verbatim. In particular the widget keeps
# com.apple.security.app-sandbox: PlugInKit silently refuses to register an
# unsandboxed .appex, so dropping it produces a bundle that looks correct on
# disk and never appears in the widget gallery. Ad-hoc signing accepts both the
# sandbox and the App Group entitlement here.
# ---------------------------------------------------------------------------
echo "==> Signing (ad-hoc)"
codesign --force --sign - \
    --identifier "$WIDGET_BUNDLE_ID" \
    --entitlements "$ROOT/Widget/MikroTikWidget.entitlements" \
    "$APPEX"

codesign --force --sign - \
    --identifier "$APP_BUNDLE_ID" \
    --entitlements "$ROOT/App/MikroTikDashboard.entitlements" \
    "$BUNDLE"

codesign --verify --deep --strict "$BUNDLE"

# ---------------------------------------------------------------------------
# 6. Verification
# ---------------------------------------------------------------------------
if [[ ! -x "$APPEX/Contents/MacOS/$WIDGET_NAME" ]]; then
    echo "error: widget extension missing from $APPEX" >&2
    exit 1
fi

if ! codesign -d --entitlements :- "$APPEX" 2>/dev/null | grep -q "app-sandbox"; then
    echo "error: $WIDGET_NAME.appex is not sandboxed; it will not register as a widget" >&2
    exit 1
fi

echo
echo "Built: $BUNDLE"
echo "       $APPEX"
echo
echo "The widget gallery lists extensions that PlugInKit has registered, which"
echo "happens when the containing app is installed and launched:"
echo "  cp -R \"$BUNDLE\" /Applications/ && open /Applications/$APP_NAME.app"
echo
echo "Confirm registration with:"
echo "  pluginkit -m -v -p com.apple.widgetkit-extension | grep mikrotik"
