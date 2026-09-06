#!/bin/bash
# 跑專案的檢查腳本。目前只有圓角偵測 —— 它的幾何換算夠微妙，值得有回歸測試。
# 這裡不用 XCTest：executable target 要拆成 library 才好測，為一個檔案不值得。
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 圓角偵測"
swiftc -O -o "$WORK/corner-detection" \
    Sources/Glassmorphism/CornerDetection.swift \
    Tools/tests/corner-detection/main.swift
"$WORK/corner-detection"
