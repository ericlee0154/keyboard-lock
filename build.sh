#!/bin/sh
# Builds KeyboardLock.app next to this script. `./build.sh install` also copies it to
# /Applications and starts it.
set -e
cd "$(dirname "$0")"
APP=KeyboardLock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/KeyboardLock"
ID=$(security find-identity -v -p codesigning | awk 'NR==1 && /\)/ {print $2}')
codesign --force --sign "${ID:--}" "$APP"
if [ "$1" = install ]; then
    # Wait for the old one to go, or `open` just brings it forward.
    pkill -x KeyboardLock 2>/dev/null && while pgrep -xq KeyboardLock; do sleep 0.2; done
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open "/Applications/$APP"
fi
