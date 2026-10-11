#!/usr/bin/env bash
# ============================================================
#  Vosmenog — обновление метод-контента (безопасное)
#  Тянет свежий репо и раскладывает текст метода + конфиг агента
#  (agents/Vosmenog.md раскатывается с ПЕРЕНОСОМ локального
#  периметра: deny на боевые каталоги, дописанные setup.sh,
#  не теряются) + TUI-плагины (tui.json, plugins/).
#  НЕ трогает: журнал памяти, .bashrc. Конфиг opencode (opencode.json) и
#  ~/.claude/CLAUDE.md — только ДОПИСЫВАЕТ карту сервера, если её там нет
#  (блок 2h, с бэкапом); остальное в них меняешь осознанно через setup.sh.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SCRIPT_DIR/harness"      # метод, вход, инструменты, адаптеры (EPIC-026 Ф4)
VOS="$SCRIPT_DIR/vosmenog"         # Восьменог: персона и продукт для opencode
AGENT_OS="$HOME/agent-os"
OC_CONF="$HOME/.config/opencode"
# Режим «только харнесс»: флаг или метка, оставленная setup.sh --harness-only.
HARNESS_ONLY=0
for a in "$@"; do [ "$a" = "--harness-only" ] && HARNESS_ONLY=1; done
[ -f "$AGENT_OS/.harness-only" ] && HARNESS_ONLY=1
MEMORY="$OC_CONF/memory"
AGENTS="$OC_CONF/agents"

ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

printf '\n\033[1;36m==> Обновление Vosmenog (метод-контент)\033[0m\n'

# 1. подтянуть репо (только fast-forward — без молчаливых мержей)
cd "$SCRIPT_DIR"

# 1a. сторож источника: раскатываем незакоммиченное — предупреждаем.
#     Этот скрипт живёт в ИСТОЧНИКЕ ($SCRIPT_DIR); установка (~/agent-os) своего
#     git не имеет и получает только копии. Незакоммиченная правка здесь
#     раскатается на машину, но не уедет в репозиторий — и разойдётся с тем,
#     что увидят остальные установки. Untracked не смотрим: рабочий мусор.
DIRTY="$(git status --porcelain --untracked-files=no 2>/dev/null || true)"
if [ -n "$DIRTY" ]; then
  warn "в источнике есть НЕзакоммиченные правки — раскатаю, но в репозиторий они не уедут:"
  printf '%s\n' "$DIRTY" | sed 's/^/      /'
  warn "закоммить и запушь, иначе установка разойдётся с дистрибутивом."
  printf '\n'
fi

OLD_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
if ! git pull --ff-only; then
  die "git pull не прошёл (локальные правки или расхождение). Разберись вручную: cd $SCRIPT_DIR && git status"
fi
NEW_HEAD="$(git rev-parse HEAD)"

# 1b. перезапуск, если pull обновил сам этот скрипт.
#     bash дочитывает файл по ходу исполнения: если git pull подменил update.sh
#     под ним, дальше выполняются куски вперемешку со старым кодом, и шаги,
#     добавленные обновлением, молча не применяются (скрипт при этом
#     рапортует «Готово»). Перезапускаемся ровно один раз, флагом от рекурсии,
#     передав исходный HEAD, чтобы changelog не потерялся.
if [ "${VOSMENOG_UPDATE_RESTARTED:-}" != "1" ] && [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
  export VOSMENOG_UPDATE_RESTARTED=1
  export VOSMENOG_UPDATE_OLD_HEAD="$OLD_HEAD"
  exec bash "$SCRIPT_DIR/update.sh" "$@"
fi
[ -n "${VOSMENOG_UPDATE_OLD_HEAD:-}" ] && OLD_HEAD="$VOSMENOG_UPDATE_OLD_HEAD"

if [ -n "$OLD_HEAD" ] && [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
  printf '\n\033[1;36m==> Что изменилось (%s..%s)\033[0m\n' "${OLD_HEAD:0:7}" "${NEW_HEAD:0:7}"
  git log --oneline "$OLD_HEAD..$NEW_HEAD"
  printf '\n  Файлы:\n'
  git diff --name-only "$OLD_HEAD..$NEW_HEAD" | sed 's/^/    /'
else
  printf '\n  Уже на актуальной версии — новых коммитов нет.\n'
fi

# 2. разложить ТОЛЬКО метод-контент
[ -d "$HARNESS" ] && [ -d "$VOS" ] || die "нет harness/ и vosmenog/ — это точно клон репо?"
mkdir -p "$AGENT_OS" "$MEMORY"
# Копируем ВСЕГДА, снимая симлинк, если он остался от старой схемы.
# Раньше здесь была ветка «на месте симлинк → он актуален после git pull,
# не копируем». Она была верна, пока установка была git-клоном. После снятия
# .git (2026-09-09) симлинк стал указывать на замороженный payload, и файл
# переставал обновляться молча. Установка копий не боится: она никуда не пушится.
DOCS="METHOD.md BOOT.md GUIDE.md README.md INSTALL_PROMPT.md FOREIGN_AGENTS.md CLAUDE_CODE_MINOTAUR.md AGENTS_INSTALL.md EPIC.template.md TASK.template.md BUG.template.md project-slots.template.md ROADMAP.template.md"
[ "$HARNESS_ONLY" = "1" ] || DOCS="METHOD.md BOOT.md ONBOARDING.md GUIDE.md README.md INSTALL_PROMPT.md FOREIGN_AGENTS.md CLAUDE_CODE_MINOTAUR.md AGENTS_INSTALL.md EPIC.template.md TASK.template.md BUG.template.md project-slots.template.md ROADMAP.template.md"
for f in $DOCS; do
  SRC_F=""
  for d in "$HARNESS" "$VOS" "$SCRIPT_DIR"; do [ -f "$d/$f" ] && { SRC_F="$d/$f"; break; }; done   # часть доков лежит в корне репо
  if [ -n "$SRC_F" ]; then
    [ -L "$AGENT_OS/$f" ] && rm -f "$AGENT_OS/$f"
    cp "$SRC_F" "$AGENT_OS/"; ok "agent-os/$f"
  fi
done
# 2-bis. персона: раскатывается с УМНОЙ защитой.
#   Раньше персона не обновлялась никогда («защищена от затирания») — при
#   git-клоне её подтягивал pull, а после снятия .git защита превратилась в
#   заморозку: правки дистрибутива до агента не доезжали.
#   Теперь: помним хеш того, что раскатали в прошлый раз. Совпадает с тем, что
#   лежит → человек не трогал, спокойно обновляем. Не совпадает → правил
#   человек, не трогаем и говорим об этом вслух.
if [ "$HARNESS_ONLY" != "1" ]; then
PERSONA="persona_vosya.md"
PERSONA_HASH_FILE="$OC_CONF/.vosmenog-persona-hash"
if [ -f "$VOS/$PERSONA" ]; then
  [ -L "$AGENT_OS/$PERSONA" ] && rm -f "$AGENT_OS/$PERSONA"
  if [ ! -f "$AGENT_OS/$PERSONA" ]; then
    cp "$VOS/$PERSONA" "$AGENT_OS/$PERSONA"
    md5sum < "$AGENT_OS/$PERSONA" | cut -d' ' -f1 > "$PERSONA_HASH_FILE"
    ok "agent-os/$PERSONA (персона поставлена)"
  else
    CUR="$(md5sum < "$AGENT_OS/$PERSONA" | cut -d' ' -f1)"
    PREV="$(cat "$PERSONA_HASH_FILE" 2>/dev/null || true)"
    if [ -n "$PREV" ] && [ "$CUR" != "$PREV" ]; then
      warn "$PERSONA правлена руками — НЕ обновляю (твоя настройка голоса важнее)."
      printf '        diff %s %s\n' "$AGENT_OS/$PERSONA" "$VOS/$PERSONA"
      printf '        правку стоит перенести в источник, иначе она не переживёт переустановку\n'
    else
      cp "$VOS/$PERSONA" "$AGENT_OS/$PERSONA"
      md5sum < "$AGENT_OS/$PERSONA" | cut -d' ' -f1 > "$PERSONA_HASH_FILE"
      ok "agent-os/$PERSONA (персона обновлена)"
    fi
  fi
fi
fi

if [ -d "$HARNESS/method" ]; then
  mkdir -p "$AGENT_OS/method"
  cp "$HARNESS/method/"*.md "$AGENT_OS/method/"; ok "agent-os/method/ (разделы метода по фазе)"
fi
cp "$HARNESS/STARTUP.md" "$MEMORY/STARTUP.md"; ok "memory/STARTUP.md (протокол)"
cp "$HARNESS/next-session.template.md" "$MEMORY/next-session.template.md"; ok "memory/next-session.template.md (шаблон горячей памяти)"

# 2a. глобальный слот инструкций opencode.
#     opencode берёт первый существующий из [<config>/AGENTS.md, ~/.claude/CLAUDE.md]:
#     пустой первый слот = чужой роутер (Claude Code) затекает в контекст агента.
[ "$HARNESS_ONLY" = "1" ] || { cp "$VOS/global-AGENTS.md" "$OC_CONF/AGENTS.md"; ok "AGENTS.md (глобальный слот инструкций)"; }
cp "$HARNESS/memory-guard.sh" "$MEMORY/memory-guard.sh"; chmod +x "$MEMORY/memory-guard.sh"; ok "memory/memory-guard.sh (сторож бюджета памяти)"
cp "$HARNESS/update-check.sh" "$MEMORY/update-check.sh"; chmod +x "$MEMORY/update-check.sh"; ok "memory/update-check.sh (сторож обновлений)"

# 2b. разложить скиллы (метод-контент: чистые инструкции, прав не несут)
SKILLS="$HOME/.config/opencode/skills"
if [ -d "$HARNESS/skills" ]; then
  mkdir -p "$SKILLS"
  cp -r "$HARNESS/skills/." "$SKILLS/"; ok "skills/ харнесса (readiness, env-profile, server-audit, oom-guard, infra-bootstrap)"
fi
if [ "$HARNESS_ONLY" != "1" ] && [ -d "$VOS/skills" ]; then
  mkdir -p "$SKILLS"
  cp -r "$VOS/skills/." "$SKILLS/"; ok "skills/ Восьменога (tutor, help, course-project)"
fi

# 2c. раскатать конфиг агента (agents/Vosmenog.md)
#     с ПЕРЕНОСОМ локального периметра: deny на боевые каталоги,
#     дописанные setup.sh, переносятся в свежий конфиг.
if [ "$HARNESS_ONLY" != "1" ] && [ -f "$VOS/agents/Vosmenog.md" ]; then
  mkdir -p "$AGENTS"
  TMP_DENY=""
  if [ -f "$AGENTS/Vosmenog.md" ]; then
    TMP_DENY="$(mktemp)"
    python3 - "$AGENTS/Vosmenog.md" "$VOS/agents/Vosmenog.md" "$TMP_DENY" << 'PYEOF'
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
  cp "$VOS/agents/Vosmenog.md" "$AGENTS/Vosmenog.md"
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
if [ -d "$HARNESS/head-kit" ]; then
  mkdir -p "$AGENT_OS/head-kit"
  cp "$HARNESS/head-kit/"*.md "$AGENT_OS/head-kit/"; ok "agent-os/head-kit/ (кит головы)"
  # индикатор доверия и команда смены — тоже инструменты головы (Claude Code):
  # раньше их брали из payload установки, который после снятия .git стал мёртв.
  [ -f "$HARNESS/statusline.sh" ] && cp "$HARNESS/statusline.sh" "$AGENT_OS/head-kit/statusline.sh"
  [ -f "$HARNESS/commands/trust.md" ] && cp "$HARNESS/commands/trust.md" "$AGENT_OS/head-kit/trust.md"
  ok "agent-os/head-kit/statusline.sh + trust.md (инструменты головы)"
fi

# 2e. TUI-плагины (панель доверия и др.) — tui.json + plugins/
if [ "$HARNESS_ONLY" != "1" ]; then
if [ -f "$VOS/tui.json" ]; then
  cp "$VOS/tui.json" "$OC_CONF/tui.json"; ok "tui.json (конфиг TUI-плагинов)"
fi
if [ -d "$VOS/plugins" ]; then
  mkdir -p "$OC_CONF/plugins"
  cp "$VOS/plugins/"*.tsx "$OC_CONF/plugins/" 2>/dev/null; ok "plugins/ (TUI-плагины)"
fi
fi

# 2g. инструменты раскладки (EPIC-025): индекс проектов и рабочие ветки.
#     Правила — agent-os/method/layout.md; хук старта зовёт projects-index.py --summary.
if [ -d "$HARNESS/tools" ]; then
  mkdir -p "$AGENT_OS/bin"
  for t in "$HARNESS/tools/"*; do
    cp "$t" "$AGENT_OS/bin/"; chmod +x "$AGENT_OS/bin/$(basename "$t")"
  done
  ok "agent-os/bin/ (projects-index.py, wt.sh, evm — раскладка и единый вход)"
fi
# 2g-bis. команда evm в PATH: симлинк на УСТАНОВЛЕННУЮ копию (не на payload/ —
#         урок заморозки симлинков 2026-09-09). Чужой файл с таким именем не трогаем.
EVM_LINK="$HOME/.local/bin/evm"
if [ -x "$AGENT_OS/bin/evm" ]; then
  mkdir -p "$HOME/.local/bin"
  if [ -L "$EVM_LINK" ] || [ ! -e "$EVM_LINK" ]; then
    ln -sfn "$AGENT_OS/bin/evm" "$EVM_LINK"; ok "~/.local/bin/evm → agent-os/bin/evm"
  else
    warn "~/.local/bin/evm — чужой файл, не трогаю"
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin нет в PATH — добавь, иначе evm не найдётся" ;; esac
fi

# 2h. карта сервера (EPIC-026, решение Р7): только ДОБАВЛЯЕМ строку в opencode.json
#     и импорт в ~/.claude/CLAUDE.md, если их нет. Идемпотентно, с бэкапом рядом.
#     Существующая карта не трогается; нет файла карты — кладётся заготовка.
python3 "$HARNESS/connect-server-map.py"

# 2i. адаптер Claude Code (EPIC-026 Ф4, Р11): общие хуки порога смены и панель, подключение в
#     ~/.claude/settings.json. Только добавление; отличающийся файл не затирается; нет ~/.claude - пропуск.
python3 "$HARNESS/adapters/claude-code/install.py"

# 2f. маркер источника: установка своего git не имеет и без этого файла
#     не знает, откуда её раскатали. По нему протокол старта (STARTUP.md,
#     «Уведомление об обновлении») ходит в источник за changelog и за
#     непритянутыми коммитами. Нет файла или путь протух — проверки молчат.
printf '%s\n' "$SCRIPT_DIR" > "$OC_CONF/.vosmenog-source"
printf '%s\n' "$NEW_HEAD" > "$OC_CONF/.vosmenog-deployed"
ok ".vosmenog-source + .vosmenog-deployed (откуда раскатано и на каком коммите)"

# 3. что НАМЕРЕННО не тронуто
printf '\n'
warn "НЕ тронуты (меняй через проект vosmenog осознанно):"
echo "    • persona_vosya.md — обновляется, но НЕ поверх ручной правки (см. выше)"
echo "    • opencode.json — конфиг (кроме одной строки карты сервера, блок 2h)"
echo "    • journal.md / archive — память (данные)"
echo "    • .vosmenog-changelog-seen — маркер показанного changelog (состояние сессии)"
echo "    • deny-периметр среды — переносится при раскатке агента (см. блок 2c)"
echo "    • tui.json — раскатывается из дистрибутива (перезаписью)"
printf '\n\033[1;32m==> Готово. Метод обновлён, барьеры и память на месте.\033[0m\n'
