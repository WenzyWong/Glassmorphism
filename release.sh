#!/bin/bash
# 發布用：編譯 arm64 + x86_64 通用二進位，打包成可上傳到 GitHub Release 的 zip。
#
# 不需要完整的 Xcode：SwiftPM 的 --arch 需要 xcbuild，這裡改成分別編譯兩個架構
# 再用 lipo 合併，Command Line Tools 就夠了。
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(cat VERSION)}"
NAME="Glassmorphism"
OUT="dist"
APP="$OUT/$NAME.app"
ZIP="$OUT/$NAME-$VERSION-macos-universal.zip"

echo "==> 版本 $VERSION"
rm -rf "$OUT" .build-arm64 .build-x86_64

echo "==> 編譯 arm64"
swift build -c release --scratch-path .build-arm64 \
    -Xswiftc -target -Xswiftc arm64-apple-macosx13.0

echo "==> 編譯 x86_64"
swift build -c release --scratch-path .build-x86_64 \
    -Xswiftc -target -Xswiftc x86_64-apple-macosx13.0

echo "==> 合併成通用二進位"
mkdir -p "$OUT"
/usr/bin/lipo -create -output "$OUT/$NAME.bin" \
    ".build-arm64/release/$NAME" ".build-x86_64/release/$NAME"
/usr/bin/lipo -info "$OUT/$NAME.bin"

echo "==> 組裝 $APP"
Tools/bundle.sh "$OUT/$NAME.bin" "$APP" "$VERSION"
rm -f "$OUT/$NAME.bin"

echo "==> 打包 $ZIP"
# 用 ditto 而不是 zip，才能保住 bundle 的符號連結與簽名
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo
echo "完成："
echo "  $APP"
echo "  $ZIP"
