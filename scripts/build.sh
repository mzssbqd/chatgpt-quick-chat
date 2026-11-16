#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
architectures=(--arch arm64 --arch x86_64)
swift build -c release "${architectures[@]}"
bin=$(swift build -c release "${architectures[@]}" --show-bin-path)
mkdir -p build
stage=$(mktemp -d build/package.XXXXXX)
trap 'rm -r "$stage"' EXIT
name=chatgpt-quick-chat
app="$stage/$name.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$stage/Chat.iconset"
cp "$bin/ChatPanel" "$contents/MacOS/ChatPanel"
for arch in arm64 x86_64; do lipo "$contents/MacOS/ChatPanel" -verify_arch "$arch"; done
ditto "$bin/chatgpt-quick-chat_ChatPanel.bundle" "$contents/Resources/chatgpt-quick-chat_ChatPanel.bundle"
"$bin/ChatPanel" --render-icon "$stage/mark.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$stage/mark.png" --out "$stage/Chat.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$stage/mark.png" --out "$stage/Chat.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/Chat.iconset" -o "$contents/Resources/Chat.icns"
cp scripts/Info.plist "$contents/Info.plist"
signature=(--sign -)
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  signature=(--sign "$DEVELOPER_ID_APPLICATION" --timestamp --options runtime)
fi
codesign --force "${signature[@]}" "$app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$contents/Info.plist")
archive="$name-$version-universal.zip"
ditto -c -k --keepParent "$app" "$stage/$archive"
if [[ -d "build/$name.app" ]]; then mv "build/$name.app" "$stage/previous.app"; fi
mv "$app" "build/$name.app"
mv "$stage/$archive" "build/$archive"
echo "build/$archive"
