#!/bin/bash
# 在 CI 裡跑一個命令，失敗時把輸出送成 annotation 與 job summary。
#
# GitHub 的 Actions 日誌對公開倉庫也需要認證才能用 API 下載，
# 但 annotation 與 summary 不用。沒有這一步，CI 一掛就得有人登入去翻日誌。
#
# 用法：ci-run.sh <標題> <命令...>
set -uo pipefail

TITLE="$1"; shift
LOG="$(mktemp)"

if "$@" 2>&1 | tee "$LOG"; then
    rm -f "$LOG"
    exit 0
fi

# 摘要：優先挑編譯錯誤，沒有就取結尾
EXCERPT="$(grep -E "error:|✗" "$LOG" | head -30)"
[ -z "$EXCERPT" ] && EXCERPT="$(tail -30 "$LOG")"

{
    echo "### ❌ $TITLE"
    echo '```'
    echo "$EXCERPT"
    echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

# annotation 只能單行，換行要編成 %0A（% 本身也得先跳脫）
MESSAGE="$(printf '%s' "$EXCERPT" | head -20 \
    | sed -e 's/%/%25/g' -e 's/\r/%0D/g' \
    | awk '{ printf "%s%%0A", $0 }')"
echo "::error title=${TITLE}::${MESSAGE}"

rm -f "$LOG"
exit 1
