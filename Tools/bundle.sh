#!/bin/bash
# 把已編譯好的執行檔組裝成 .app bundle。
# 用法：bundle.sh <執行檔路徑> <輸出的 .app 路徑> <版本號>
set -euo pipefail
BIN="$1"; APP="$2"; VERSION="$3"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glassmorphism"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# 臨時簽名。沒有付費開發者帳號就只能這樣，使用者首次開啟需要繞過 Gatekeeper（見 README）。
codesign --force --sign - --timestamp=none "$APP" >/dev/null
