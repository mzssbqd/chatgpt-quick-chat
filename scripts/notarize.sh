#!/bin/bash
# Sign and notarize a distribution copy of the locally tested app.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID_APPLICATION:?请指定 Developer ID Application 签名身份}"
: "${NOTARY_PROFILE:?请指定 notarytool 的钥匙串配置名称}"

name=chatgpt-quick-chat
source_app="build/$name.app"
if [[ ! -d "$source_app" ]]; then
  echo "请先运行 bash scripts/build.sh 生成通用应用。" >&2
  exit 1
fi
stage=$(mktemp -d build/notarize.XXXXXXXX)
trap 'rm -r "$stage"' EXIT
app="$stage/$name.app"
ditto "$source_app" "$app"
for arch in arm64 x86_64; do lipo "$app/Contents/MacOS/ChatPanel" -verify_arch "$arch"; done
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
# Validate the Developer ID Application certificate extension before submitting.
codesign --verify --strict --deep --all-architectures -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"

ditto -c -k --keepParent "$app" "$stage/submit.zip"
receipt="$stage/submission.plist"
xcrun notarytool submit "$stage/submit.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$receipt"
result=$(/usr/libexec/PlistBuddy -c 'Print :status' "$receipt")
if [[ "$result" != Accepted ]]; then
  request_id=$(/usr/libexec/PlistBuddy -c 'Print :id' "$receipt")
  echo "公证状态为 $result，提交编号 $request_id。" >&2
  exit 1
fi
xcrun stapler staple "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="$name-$version-notarized.zip"
ditto -c -k --keepParent "$app" "$stage/$archive"
mkdir "$stage/verify"
ditto -x -k "$stage/$archive" "$stage/verify"
final="$stage/verify/$name.app"
codesign --verify --strict --deep --all-architectures "$final"
xcrun stapler validate "$final"
spctl --assess --type execute --verbose "$final"
mv "$stage/$archive" "build/$archive"
shasum -a 256 "build/$archive"
