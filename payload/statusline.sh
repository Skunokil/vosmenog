#!/bin/bash
# Минотавр — индикатор уровня доверия в statusLine.
# Источник истины (единый для Восьменога и Минотавра):
#   ~/.config/opencode/memory/user-profile.md → trust_level (yaml-блок)
# Правит /trust (пишет в тот же файл) или панель Восьменога (alt+1/2/3).
# Легенда: красный = продвинутый (опасный уровень автоматизации/делегирования воли),
# жёлтый = средний, зелёный = обучающий.
profile_file="$HOME/.config/opencode/memory/user-profile.md"
level=$(grep -m1 '^\s*trust_level:\s*\S' "$profile_file" 2>/dev/null | sed 's/.*trust_level:[[:space:]]*//' | cut -d'#' -f1 | tr -d '[:space:]')
[ -z "$level" ] && level="обучающий"

case "$level" in
  продвинутый) color=$'\033[31m' ;;  # красный — опасный уровень автоматизации
  средний)     color=$'\033[33m' ;;  # жёлтый
  *)           color=$'\033[32m' ;;  # зелёный (обучающий/неизвестно)
esac
reset=$'\033[0m'

printf '🐂 Минотавр · %s%s%s\n' "$color" "$level" "$reset"
