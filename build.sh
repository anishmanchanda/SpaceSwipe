#!/bin/sh
# Builds, signs and installs /Applications/SpaceSwipe.app.
# Uses your first code-signing identity (e.g. Apple Development). A stable identity keeps the
# Accessibility grant valid across rebuilds; ad-hoc signing (fallback) needs re-granting each build.
set -e
cd "$(dirname "$0")"
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | awk 'NR==1 && $2 ~ /^[0-9A-F]{40}$/ {print $2}')}"
APP="/Applications/SpaceSwipe.app"
STAGE="build/SpaceSwipe.app" # assembled here, then moved, so a failed build never touches the installed app
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
clang -c -O2 -Wall Sources/DockSwipe.c -o build/DockSwipe.o
swiftc -O -swift-version 5 -import-objc-header Sources/DockSwipe.h Sources/main.swift build/DockSwipe.o \
  -F/System/Library/PrivateFrameworks -framework SkyLight -framework IOKit -o "$STAGE/Contents/MacOS/SpaceSwipe"
cp Info.plist "$STAGE/Contents/Info.plist"
cp icon/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
codesign --force --sign "${IDENTITY:--}" "$STAGE"
"$STAGE/Contents/MacOS/SpaceSwipe" --selftest
rm -rf "$APP"
mv "$STAGE" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Installed $APP (signed with ${IDENTITY:-ad-hoc})"
