#!/bin/sh
# Builds, signs and installs ~/Applications/SpaceSwipe.app.
# Uses your first code-signing identity (e.g. Apple Development). A stable identity keeps the
# Accessibility grant valid across rebuilds; ad-hoc signing (fallback) needs re-granting each build.
set -e
cd "$(dirname "$0")"
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | awk 'NR==1 && $2 ~ /^[0-9A-F]{40}$/ {print $2}')}"
APP="$HOME/Applications/SpaceSwipe.app"
mkdir -p build "$APP/Contents/MacOS"
clang -c -O2 -Wall Sources/DockSwipe.c -o build/DockSwipe.o
swiftc -O -swift-version 5 -import-objc-header Sources/DockSwipe.h Sources/main.swift build/DockSwipe.o \
  -F/System/Library/PrivateFrameworks -framework SkyLight -framework IOKit -o "$APP/Contents/MacOS/SpaceSwipe"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${IDENTITY:--}" "$APP"
"$APP/Contents/MacOS/SpaceSwipe" --selftest
echo "Installed $APP (signed with ${IDENTITY:-ad-hoc})"
