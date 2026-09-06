#!/bin/bash
# 跑專案的檢查腳本。
# 這裡不用 XCTest：executable target 要先拆成 library 才好測，為這幾個檔案不值得。
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 圓角偵測的幾何換算夠微妙（少了 √r 修正會固定量短），需要回歸測試
echo "==> 圓角偵測"
swiftc -O -o "$WORK/corner-detection" \
    Sources/Glassmorphism/CornerDetection.swift \
    Tools/tests/corner-detection/main.swift
"$WORK/corner-detection"

echo
echo "==> 磁吸對齊"
swiftc -O -o "$WORK/snapping" \
    Sources/Glassmorphism/Snapping.swift \
    Sources/Glassmorphism/Model.swift \
    Sources/Glassmorphism/Localization.swift \
    Sources/Glassmorphism/Renderer.swift \
    Sources/Glassmorphism/CornerDetection.swift \
    Tools/tests/snapping/main.swift
"$WORK/snapping"
