#!/bin/sh
# Builds KeyboardLock.app next to this script. `./build.sh install` also copies it to
# /Applications and starts it.
set -e
cd "$(dirname "$0")"
APP=KeyboardLock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/KeyboardLock"
ID=$(security find-identity -v -p codesigning | awk 'NR==1 && /\)/ {print $2}')
codesign --force --sign "${ID:--}" "$APP"
if [ "$1" = install ]; then
    pkill -x KeyboardLock 2>/dev/null || true
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open "/Applications/$APP"
fi
