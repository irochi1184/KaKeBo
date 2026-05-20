#!/bin/bash
# AppGroup ID 整合性チェックスクリプト
# pre-commit hook および Xcode Build Phase から呼び出される
#
# 背景: v2.3.1 で AppGroup ID が誤って変更され、ユーザーデータが
# 一時的に見えなくなるインシデントが発生した。二度と起こさないためのガード。

set -euo pipefail

EXPECTED_ID="group.com.irochiTech.KaKeBo"

# プロジェクトルートを特定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILES=(
    "Shared/AppGroup.swift"
    "KaKeBo/KaKeBo.entitlements"
    "KaKeBoWidgetExtension.entitlements"
)

ERRORS=0

for file in "${FILES[@]}"; do
    filepath="$PROJECT_ROOT/$file"
    if [ ! -f "$filepath" ]; then
        echo "ERROR: $file が見つかりません"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if ! grep -q "$EXPECTED_ID" "$filepath"; then
        echo "ERROR: $file に正しい AppGroup ID ($EXPECTED_ID) が含まれていません"
        ERRORS=$((ERRORS + 1))
    fi
done

# AppGroup.swift の id 定数が正しいことを厳密にチェック
APPGROUP_SWIFT="$PROJECT_ROOT/Shared/AppGroup.swift"
if [ -f "$APPGROUP_SWIFT" ]; then
    ACTUAL_ID=$(grep -o 'static let id = "[^"]*"' "$APPGROUP_SWIFT" | grep -o '"[^"]*"' | tr -d '"')
    if [ "$ACTUAL_ID" != "$EXPECTED_ID" ]; then
        echo "ERROR: AppGroup.swift の id が \"$ACTUAL_ID\" になっています。正しくは \"$EXPECTED_ID\" です"
        ERRORS=$((ERRORS + 1))
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "===================================================="
    echo " AppGroup ID が変更されています!"
    echo " これはユーザーデータ消失を引き起こします。"
    echo " 正しい値: $EXPECTED_ID"
    echo "===================================================="
    exit 1
fi

echo "AppGroup ID チェック OK: $EXPECTED_ID"
exit 0
