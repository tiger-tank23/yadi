#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app=build/Payload/PhoneBridge.app
mkdir -p "$app"
xcrun --sdk iphoneos clang -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -arch arm64 -miphoneos-version-min=16.0 -fobjc-arc -fmodules -O2 \
  main.m CWJPEGInstrument.m -framework UIKit -framework Foundation \
  -framework WebKit -framework QuartzCore -framework CoreGraphics -o "$app/PhoneBridge"
cp media.html "$app/"
cp Info.plist "$app/"
plutil -lint "$app/Info.plist"
(cd build && zip -qr PhoneBridge-unsigned.ipa Payload)
