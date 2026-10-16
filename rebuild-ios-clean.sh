#!/bin/bash
# Перезбірка iOS через Bazel + перевірка coverage_masks + регенерація Xcode-проєкту.
# Кеш /Users/parafon/telegram-bazel-cache НЕ видаляється. Без clean — вже зібране перевикористовується.
set -euo pipefail
cd "$(dirname "$0")"
BAZEL="$PWD/build-input/bazel-8.4.2-darwin-arm64"
RC=(--bazelrc=.bazelrc --bazelrc=xcodeproj.bazelrc)

echo "==> build"
"$BAZEL" "${RC[@]}" build //Telegram:Telegram --cpu=ios_arm64 --config=rules_xcodeproj
echo "==> перевірка coverage_masks у виході"
N=$(find "$("$BAZEL" "${RC[@]}" info bazel-bin)/Telegram" -name '*coverage_masks.json' 2>/dev/null | wc -l | tr -d ' ')
echo "знайдено coverage_masks.json: $N (очікується 9)"
[ "$N" -ge 9 ] || { echo "ПОМИЛКА: масок немає в білді"; exit 1; }
echo "==> xcodeproj"
"$BAZEL" "${RC[@]}" run //Telegram:Telegram_xcodeproj
echo "ГОТОВО"
