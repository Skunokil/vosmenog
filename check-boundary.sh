#!/usr/bin/env bash
# Проверка границы слоёв (EPIC-026 Ф4, AC-3): харнесс не знает про Восьменога.
#   1. Ни один файл harness/ не ссылается на пути внутри vosmenog/ репозитория.
#   2. Код харнесса (py, sh, json, evm) не называет файлы продукта (Vosmenog.md,
#      persona_vosya, opencode.json, tui.json, trust-panel), кроме явного allowlist.
# Документы (md) о ролях говорить могут: «руки» - роль метода, а не файл продукта.
# Запуск руками из корня репозитория: ./check-boundary.sh   (код возврата 1 - нарушение)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2

# Allowlist: файл|причина. Каждая запись - СЛОТ УСТАНОВКИ, а не зависимость:
# файла нет - код молча пропускает, харнесс работает без Восьменога.
ALLOW=(
  "harness/connect-server-map.py|подключение карты сервера в opencode.json, если он есть (слот среды opencode)"
  "harness/tools/evm|роль hands показывает файл персоны, если он установлен (слот персоны)"
  "harness/memory-guard.sh|бюджет старта суммирует то, что читается всегда, если файл есть"
)

bad=0
echo "== 1. пути в vosmenog/ из harness/"
hits=$(grep -rnE "vosmenog/(persona_vosya|agents|skills|plugins|opencode\.json|tui\.json|global-AGENTS)" harness || true)
if [ -n "$hits" ]; then echo "$hits"; bad=1; else echo "   чисто"; fi

echo "== 2. код харнесса, называющий файлы продукта"
allow_files=$(printf '%s\n' "${ALLOW[@]}" | cut -d'|' -f1)
hits=$(grep -rnE "Vosmenog\.md|persona_vosya|opencode\.json|tui\.json|trust-panel" harness \
        --include=*.py --include=*.sh --include=evm --include=*.json || true)
rest=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  f="${line%%:*}"
  grep -qxF "$f" <<<"$allow_files" || rest+="$line"$'\n'
done <<<"$hits"
if [ -n "$rest" ]; then printf '%s' "$rest"; bad=1; else echo "   чисто"; fi

echo "== allowlist (слоты, не нарушения)"
for a in "${ALLOW[@]}"; do echo "   ${a%%|*} - ${a#*|}"; done
[ "$bad" = 0 ] && echo "ГРАНИЦА ЦЕЛА" || echo "ГРАНИЦА НАРУШЕНА"
exit "$bad"
