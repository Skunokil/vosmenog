#!/usr/bin/env bash
# ============================================================
#  Vosmenog — обновление метод-контента (безопасное)
#  Тянет свежий репо и раскладывает ТОЛЬКО текст метода.
#  НЕ трогает: права/периметр Vosmenog, конфиг opencode,
#  журнал памяти, .bashrc. Их меняешь осознанно через setup.sh.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
AGENT_OS="$HOME/agent-os"
MEMORY="$HOME/.config/opencode/memory"

ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

printf '\n\033[1;36m==> Обновление Vosmenog (метод-контент)\033[0m\n'

# 1. подтянуть репо (только fast-forward — без молчаливых мержей)
cd "$SCRIPT_DIR"
if ! git pull --ff-only; then
  die "git pull не прошёл (локальные правки или расхождение). Разберись вручную: cd $SCRIPT_DIR && git status"
fi

# 2. разложить ТОЛЬКО метод-контент
[ -d "$PAYLOAD" ] || die "нет payload/ — это точно клон репо?"
mkdir -p "$AGENT_OS" "$MEMORY"
for f in METHOD.md ONBOARDING.md EPIC.template.md TASK.template.md BUG.template.md \
         project-slots.template.md persona_vosya.md; do
  if [ -f "$PAYLOAD/$f" ]; then cp "$PAYLOAD/$f" "$AGENT_OS/"; ok "agent-os/$f"; fi
done
cp "$PAYLOAD/STARTUP.md" "$MEMORY/STARTUP.md"; ok "memory/STARTUP.md (протокол)"

# 2b. разложить скиллы (метод-контент: чистые инструкции, прав не несут)
SKILLS="$HOME/.config/opencode/skills"
if [ -d "$PAYLOAD/skills" ]; then
  mkdir -p "$SKILLS"
  cp -r "$PAYLOAD/skills/." "$SKILLS/"; ok "skills/ (tutor и др.)"
fi

# 3. что НАМЕРЕННО не тронуто
printf '\n'
warn "НЕ тронуты (меняй через setup.sh осознанно):"
echo "    • agents/Vosmenog.md — права и периметр"
echo "    • opencode.json — конфиг"
echo "    • journal.md / archive — память (данные)"
printf '\n\033[1;32m==> Готово. Метод обновлён, барьеры и память на месте.\033[0m\n'
