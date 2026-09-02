#!/bin/bash
# 開發用：編譯目前這台機器的架構，組出 dist/Glassmorphism.app
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(cat VERSION)"

echo "==> 編譯 (release, $(uname -m))"
swift build -c release

echo "==> 組裝 dist/Glassmorphism.app"
Tools/bundle.sh ".build/release/Glassmorphism" "dist/Glassmorphism.app" "$VERSION"

echo "完成：dist/Glassmorphism.app (v$VERSION)"
echo "開啟：open dist/Glassmorphism.app"
