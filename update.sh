#!/usr/bin/env bash
# ============================================================
#  Vosmenog — обновление метод-контента (безопасное)
#  Тянет свежий репо и раскладывает текст метода + конфиг агента
#  (agents/Vosmenog.md раскатывается с ПЕРЕНОСОМ локального
#  периметра: deny на боевые каталоги, дописанные setup.sh,
#  не теряются) + TUI-плагины (tui.json, plugins/).
#  НЕ трогает: конфиг opencode (opencode.json), журнал памяти,
#  .bashrc. Их меняешь осознанно через setup.sh.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
AGENT_OS="$HOME/agent-os"
OC_CONF="$HOME/.config/opencode"
MEMORY="$OC_CONF/memory"
AGENTS="$OC_CONF/agents"

ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

printf '\n\033[1;36m==> Обновление Vosmenog (метод-контент)\033[0m\n'

# 1. подтянуть репо (только fast-forward — без молчаливых мержей)
cd "$SCRIPT_DIR"
OLD_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
if ! git pull --ff-only; then
  die "git pull не прошёл (локальные правки или расхождение). Разберись вручную: cd $SCRIPT_DIR && git status"
fi
NEW_HEAD="$(git rev-parse HEAD)"

if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
  printf '\n\033[1;36m==> Что изменилось (%s..%s)\033[0m\n' "${OLD_HEAD:0:7}" "${NEW_HEAD:0:7}"
  git log --oneline "$OLD_HEAD..$NEW_HEAD"
  printf '\n  Файлы:\n'
  git diff --name-only "$OLD_HEAD..$NEW_HEAD" | sed 's/^/    /'
else
  printf '\n  Уже на актуальной версии — новых коммитов нет.\n'
fi

# 2. разложить ТОЛЬКО метод-контент
[ -d "$PAYLOAD" ] || die "нет payload/ — это точно клон репо?"
mkdir -p "$AGENT_OS" "$MEMORY"
for f in METHOD.md ONBOARDING.md EPIC.template.md TASK.template.md BUG.template.md \
         project-slots.template.md; do
  if [ -f "$PAYLOAD/$f" ]; then
    if [ -L "$AGENT_OS/$f" ]; then
      # симлинк уже указывает на payload/$f — актуален после git pull, не копируем
      ok "agent-os/$f (symlink)"
    else
      cp "$PAYLOAD/$f" "$AGENT_OS/"; ok "agent-os/$f"
    fi
  fi
done
cp "$PAYLOAD/STARTUP.md" "$MEMORY/STARTUP.md"; ok "memory/STARTUP.md (протокол)"

# 2b. разложить скиллы (метод-контент: чистые инструкции, прав не несут)
SKILLS="$HOME/.config/opencode/skills"
if [ -d "$PAYLOAD/skills" ]; then
  mkdir -p "$SKILLS"
  cp -r "$PAYLOAD/skills/." "$SKILLS/"; ok "skills/ (tutor и др.)"
fi

# 2c. раскатать конфиг агента (agents/Vosmenog.md)
#     с ПЕРЕНОСОМ локального периметра: deny на боевые каталоги,
#     дописанные setup.sh, переносятся в свежий конфиг.
if [ -f "$PAYLOAD/agents/Vosmenog.md" ]; then
  mkdir -p "$AGENTS"
  TMP_DENY=""
  if [ -f "$AGENTS/Vosmenog.md" ]; then
    TMP_DENY="$(mktemp)"
    python3 - "$AGENTS/Vosmenog.md" "$PAYLOAD/agents/Vosmenog.md" "$TMP_DENY" << 'PYEOF'
import re, sys
live, payload, out = sys.argv[1], sys.argv[2], sys.argv[3]
def denies(src):
    return set(re.findall(r'^\s{4}"([^"]+)": deny', src, re.M))
# deny периметра = те, что есть в живом, но нет в дистрибутиве
local = denies(open(live).read()) - denies(open(payload).read())
# оставляем только пути (~/ или /); внутренние deny дистрибутива не трогаем
keep = sorted(p for p in local if p.startswith("~/") or p.startswith("/"))
open(out, "w").write("\n".join(keep))
PYEOF
  fi
  cp "$PAYLOAD/agents/Vosmenog.md" "$AGENTS/Vosmenog.md"
  if [ -n "$TMP_DENY" ] && [ -s "$TMP_DENY" ]; then
    python3 - "$AGENTS/Vosmenog.md" "$TMP_DENY" << 'PYEOF'
import sys
vfile, denies_file = sys.argv[1], sys.argv[2]
src = open(vfile).read()
marker = "    # При установке сюда дописываются"
lines = []
for p in open(denies_file):
    p = p.strip()
    if p:
        rule = f'    "{p}": deny'
        if rule not in src:
            lines.append(rule)
if lines and marker in src:
    src = src.replace(marker, "\n".join(lines) + "\n" + marker, 1)
    open(vfile, "w").write(src)
    print("  перенесено deny:", ", ".join(p.strip() for p in open(denies_file) if p.strip()))
else:
    print("  нет локального периметра — переносить нечего")
PYEOF
  fi
  [ -n "$TMP_DENY" ] && rm -f "$TMP_DENY"
  ok "agents/Vosmenog.md (права и периметр)"
fi

# 2d. кит головы (метод-контент для веб-Клода / Минотавра)
if [ -d "$PAYLOAD/shared/skills" ]; then
  mkdir -p "$AGENT_OS/head-kit"
  cp "$PAYLOAD/shared/skills/"*.md "$AGENT_OS/head-kit/"; ok "agent-os/head-kit/ (кит головы)"
fi

# 2e. TUI-плагины (панель доверия и др.) — tui.json + plugins/
if [ -f "$PAYLOAD/tui.json" ]; then
  cp "$PAYLOAD/tui.json" "$OC_CONF/tui.json"; ok "tui.json (конфиг TUI-плагинов)"
fi
if [ -d "$PAYLOAD/plugins" ]; then
  mkdir -p "$OC_CONF/plugins"
  cp "$PAYLOAD/plugins/"*.tsx "$OC_CONF/plugins/" 2>/dev/null; ok "plugins/ (TUI-плагины)"
fi

# 3. что НАМЕРЕННО не тронуто
printf '\n'
warn "НЕ тронуты (меняй через проект vosmenog осознанно):"
echo "    • persona_vosya.md — персона (защищена от затирания)"
echo "    • opencode.json — конфиг"
echo "    • journal.md / archive — память (данные)"
echo "    • deny-периметр среды — переносится при раскатке агента (см. блок 2c)"
echo "    • tui.json — раскатывается из дистрибутива (перезаписью)"
printf '\n\033[1;32m==> Готово. Метод обновлён, барьеры и память на месте.\033[0m\n'
