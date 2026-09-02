#!/bin/bash
# 重新生成 App 圖示。圖示本身是用 App 自己的 GlassRenderer 畫出來的。
# 產物 Resources/AppIcon.icns 有進版控，平常不需要跑這支。
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 編譯圖示產生器"
swiftc -O -o "$WORK/make-icon" \
    Sources/Glassmorphism/Renderer.swift \
    Sources/Glassmorphism/Model.swift \
    Sources/Glassmorphism/Localization.swift \
    Tools/make-icon/main.swift

echo "==> 繪製 1024×1024 母圖"
"$WORK/make-icon" "$WORK/master.png"

echo "==> 產生 iconset"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$WORK/master.png" --out "$ICONSET/$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "完成：Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
