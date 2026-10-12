#!/usr/bin/env bash
# ============================================================
#  Vosmenog — установщик фреймворка дисциплинированного агента
#  Раскладывает дистрибутив (harness/ и vosmenog/) по местам, сливает конфиг, ставит периметр.
#  Идемпотентен: бэкапит существующее, не клобберит чужой конфиг.
#  Кириллицу НЕ генерирует — только перекладывает готовые файлы дистрибутива.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SCRIPT_DIR/harness"      # метод, вход, инструменты, адаптеры (EPIC-026 Ф4)
VOS="$SCRIPT_DIR/vosmenog"         # Восьменог: персона и продукт для opencode

# Режим: по умолчанию ставится всё (как раньше). --harness-only — только харнесс,
# без Восьменога и opencode (машина с одним Claude Code или чужим агентом).
HARNESS_ONLY=0
for a in "$@"; do
  case "$a" in
    --harness-only) HARNESS_ONLY=1 ;;
    -h|--help) echo "setup.sh [--harness-only]   (без флага — харнесс + Восьменог)"; exit 0 ;;
    *) echo "setup.sh: неизвестный флаг '$a'" >&2; exit 2 ;;
  esac
done

OC_CONF="$HOME/.config/opencode"
AGENT_OS="$HOME/agent-os"
MEMORY="$OC_CONF/memory"
AGENTS="$OC_CONF/agents"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }

# --- 0. Проверки среды -------------------------------------
say "Проверка среды"
[ -d "$HARNESS" ] && [ -d "$VOS" ] || die "Нет папок harness/ и vosmenog/ рядом со скриптом. Запускай из корня клона."
command -v python3 >/dev/null || die "Нужен python3 (для безопасного слияния конфига)."
if command -v opencode >/dev/null; then
  ok "opencode найден: $(opencode --version 2>/dev/null || echo '?')"
else
  warn "opencode не найден в PATH. Установи его (см. GUIDE, шаг «Установка opencode»),"
  warn "затем запусти setup.sh снова. Файлы разложатся и без него, но проверить режим не выйдет."
fi

# --- 1. Структура папок ------------------------------------
say "Создание структуры"
mkdir -p "$AGENT_OS" "$MEMORY/archive" "$OC_CONF/skills"
[ "$HARNESS_ONLY" = "1" ] || mkdir -p "$AGENTS"
ok "$AGENT_OS, $MEMORY"

# --- 2. Раскладка дистрибутива ----------------------------------
say "Раскладка файлов фреймворка"
DOCS="METHOD.md BOOT.md EPIC.template.md TASK.template.md BUG.template.md project-slots.template.md ROADMAP.template.md"
[ "$HARNESS_ONLY" = "1" ] || DOCS="METHOD.md BOOT.md ONBOARDING.md EPIC.template.md TASK.template.md BUG.template.md project-slots.template.md ROADMAP.template.md"
for f in $DOCS; do
  SRC_F=""
  for d in "$HARNESS" "$VOS"; do [ -f "$d/$f" ] && { SRC_F="$d/$f"; break; }; done
  if [ -n "$SRC_F" ]; then cp "$SRC_F" "$AGENT_OS/"; ok "agent-os/$f"; fi
done
if [ "$HARNESS_ONLY" = "1" ]; then : > "$AGENT_OS/.harness-only"; ok "режим --harness-only (метка agent-os/.harness-only: update.sh её уважает)"; else rm -f "$AGENT_OS/.harness-only"; fi

if [ "$HARNESS_ONLY" != "1" ]; then
PERSONA_FILE="persona_vosya.md"
if [ -f "$VOS/$PERSONA_FILE" ]; then
  if [ ! -f "$AGENT_OS/$PERSONA_FILE" ]; then
    cp "$VOS/$PERSONA_FILE" "$AGENT_OS/"
    ok "agent-os/$PERSONA_FILE (установлен)"
  else
    warn "agent-os/$PERSONA_FILE уже есть — не перезаписан. Правь через проект, не в обход."
  fi
fi

cp "$VOS/agents/Vosmenog.md" "$AGENTS/Vosmenog.md"; ok "agents/Vosmenog.md"
else
  warn "--harness-only: персона Воси и агент Vosmenog пропущены"
fi

# Единый вход (EPIC-026 Ф3): команда evm и её помощник projects-index.py.
if [ -d "$HARNESS/tools" ]; then
  mkdir -p "$AGENT_OS/bin" "$HOME/.local/bin"
  for t in "$HARNESS/tools/"*; do
    cp "$t" "$AGENT_OS/bin/"; chmod +x "$AGENT_OS/bin/$(basename "$t")"
  done
  ok "agent-os/bin/ (evm, projects-index.py, wt.sh)"
  EVM_LINK="$HOME/.local/bin/evm"
  if [ -L "$EVM_LINK" ] || [ ! -e "$EVM_LINK" ]; then
    ln -sfn "$AGENT_OS/bin/evm" "$EVM_LINK"; ok "~/.local/bin/evm → agent-os/bin/evm"
  else
    warn "~/.local/bin/evm — чужой файл, не трогаю"
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin нет в PATH — добавь, иначе evm не найдётся" ;; esac
fi

if [ -d "$HARNESS/skills" ]; then
  cp -r "$HARNESS/skills/." "$OC_CONF/skills/"; ok "skills/ харнесса (readiness, env-profile, server-audit, oom-guard, infra-bootstrap)"
fi
if [ "$HARNESS_ONLY" != "1" ] && [ -d "$VOS/skills" ]; then
  cp -r "$VOS/skills/." "$OC_CONF/skills/"; ok "skills/ Восьменога (tutor, help, course-project)"
fi

# --- 2b. Инфраструктурный проект (эталон для скилла infra-bootstrap) ---
# Свежая установка получает заготовку ~/projects/infra + team-work/infra.
# Идемпотентно: существующее не трогаем (владелец мог уже настроить бэкап).
say "Инфраструктурный проект (~/projects/infra)"
INFRA="$HOME/projects/infra"
TEAM_INFRA="$HOME/projects/team-work/infra"
if [ -d "$HARNESS/infra-project" ]; then
  if [ ! -d "$INFRA" ]; then
    mkdir -p "$INFRA"
    cp "$HARNESS/infra-project/"*.sh \
       "$HARNESS/infra-project/.env.example" \
       "$HARNESS/infra-project/.gitignore" \
       "$HARNESS/infra-project/AGENTS.md" \
       "$HARNESS/infra-project/RESTORE.md" \
       "$HARNESS/infra-project/ROADMAP.md" "$INFRA/"
    chmod +x "$INFRA/"*.sh
    ok "infra/ развёрнут (скрипты, шаблоны). Креды добавит владелец в .env"
  else
    warn "~/projects/infra уже есть — не трогаю"
  fi
  if [ ! -d "$TEAM_INFRA" ]; then
    mkdir -p "$TEAM_INFRA/epics" "$TEAM_INFRA/backlog" "$TEAM_INFRA/sessions"
    cp "$HARNESS/infra-project/epics/EPIC-001-backup.md" "$TEAM_INFRA/epics/"
    cp "$HARNESS/infra-project/backlog/"*.md "$TEAM_INFRA/backlog/"
    printf '# Journal — Infra\n' > "$TEAM_INFRA/sessions/journal.md"
    sed 's/<проект>/infra/' "$HARNESS/next-session.template.md" > "$TEAM_INFRA/sessions/next-session.md"
    ok "team-work/infra/ развёрнут (EPIC-001-backup эталон, backlog, journal)"
  else
    warn "~/projects/team-work/infra уже есть — не трогаю"
  fi
fi

# --- 2c. Кит головы (файлы для веб-Клода / Минотавра) ------
if [ -d "$HARNESS/head-kit" ]; then
  mkdir -p "$AGENT_OS/head-kit"
  cp "$HARNESS/head-kit/"*.md "$AGENT_OS/head-kit/"; ok "agent-os/head-kit/ (session_start, персона, workflow, правила)"
fi

if [ -d "$HARNESS/method" ]; then
  mkdir -p "$AGENT_OS/method"
  cp "$HARNESS/method/"*.md "$AGENT_OS/method/"; ok "agent-os/method/ (разделы метода по фазе)"
fi
cp "$HARNESS/STARTUP.md" "$MEMORY/STARTUP.md"; ok "memory/STARTUP.md"
cp "$HARNESS/next-session.template.md" "$MEMORY/next-session.template.md"; ok "memory/next-session.template.md"
[ "$HARNESS_ONLY" = "1" ] || { cp "$VOS/global-AGENTS.md" "$OC_CONF/AGENTS.md"; ok "AGENTS.md (глобальный слот инструкций)"; }
cp "$HARNESS/memory-guard.sh" "$MEMORY/memory-guard.sh"; chmod +x "$MEMORY/memory-guard.sh"; ok "memory/memory-guard.sh (сторож бюджета памяти)"
cp "$HARNESS/update-check.sh" "$MEMORY/update-check.sh"; chmod +x "$MEMORY/update-check.sh"; ok "memory/update-check.sh (сторож обновлений: раньше его ставил только update.sh, и новый пользователь не получал уведомлений)"
if [ ! -f "$MEMORY/journal.md" ]; then
  printf '# Journal — Session Log\n' > "$MEMORY/journal.md"; ok "memory/journal.md (создан)"
else
  warn "memory/journal.md уже есть — не трогаю (память сохранена)"
fi
# user-profile.md — журнальный паттерн (есть? → не трогаю)
if [ ! -f "$MEMORY/user-profile.md" ]; then
  cp "$HARNESS/user-profile.template.md" "$MEMORY/user-profile.md"; ok "memory/user-profile.md (создан)"
else
  warn "memory/user-profile.md уже есть — не трогаю (профиль сохранён)"
fi

# --- 2d. Маркер первого запуска ------------------------------
say "Маркер первого запуска"
FIRST_RUN="$OC_CONF/.first-run"
if [ ! -f "$FIRST_RUN" ]; then
  touch "$FIRST_RUN"
  ok ".first-run создан (онбординг запустится при первом входе в opencode)"
else
  warn ".first-run уже существует — пропускаю"
fi

# --- 3. Слияние opencode.json (бережно) --------------------
if [ "$HARNESS_ONLY" != "1" ]; then
say "Конфиг opencode.json (instructions[])"
CONF_FILE="$OC_CONF/opencode.json"
if [ -f "$CONF_FILE" ]; then
  cp "$CONF_FILE" "$CONF_FILE.bak-$(date +%F-%H%M%S)"; ok "бэкап существующего конфига"
fi
python3 - "$CONF_FILE" "$VOS/opencode.json" << 'PYEOF'
import json, os, sys
conf_path, payload_path = sys.argv[1], sys.argv[2]
payload = json.load(open(payload_path))
if os.path.exists(conf_path):
    conf = json.load(open(conf_path))
else:
    conf = {"$schema": payload.get("$schema", "https://opencode.ai/config.json")}
ins = conf.setdefault("instructions", [])
for path in payload.get("instructions", []):
    if path not in ins:
        ins.append(path)
# references.memory — добавить, если нет своего
if "references" not in conf and "references" in payload:
    conf["references"] = payload["references"]
json.dump(conf, open(conf_path, "w"), indent=2, ensure_ascii=False)
print("  instructions:", ins)
PYEOF
ok "instructions подключены (STARTUP + METHOD)"
fi

# --- 3a. Карта сервера (слот SERVER.md, EPIC-026) -----------
#     Платформа знает МЕСТО карты, но не содержимое: нет файла — кладём заготовку,
#     есть — не трогаем. Подключает в opencode и (если стоит) в Claude Code.
say "Карта сервера (слот SERVER.md)"
python3 "$HARNESS/connect-server-map.py"

# --- 3b. Адаптер Claude Code (хуки порога смены и панель; только добавление) ---
say "Адаптер Claude Code"
python3 "$HARNESS/adapters/claude-code/install.py"

# --- 4. Периметр (барьер прав Vosmenog) --------------------
if [ "$HARNESS_ONLY" != "1" ]; then
say "Периметр: что агент НЕ должен трогать"
echo "  Назови каталоги прода/секретов через пробел (агенту закроется доступ)."
echo "  Пример: ~/prod-stack ~/secrets   |   Enter — пропустить."
read -r -p "  Каталоги: " PERIM || true
if [ -n "${PERIM:-}" ]; then
  # BUG-10: валидация — оставляем только токены-пути (~/... или /...), мусор отсекаем
  CLEAN=""
  for tok in $PERIM; do
    case "$tok" in
      "~/"*|/*) CLEAN="$CLEAN $tok" ;;
      *) warn "пропущен невалидный ввод: '$tok' (путь должен начинаться с ~/ или /)" ;;
    esac
  done
  CLEAN="$(echo "$CLEAN" | xargs 2>/dev/null || true)"
  if [ -z "$CLEAN" ]; then
    warn "валидных путей не распознано — периметр не изменён"
  else
    python3 - "$AGENTS/Vosmenog.md" $CLEAN << 'PYEOF'
import sys
vfile = sys.argv[1]; paths = sys.argv[2:]
src = open(vfile).read()
marker = "    # При установке сюда дописываются"
import os
lines = []
for p in paths:
    p = os.path.expanduser(p.rstrip("/"))
    rule = f'    "{p}/**": deny'
    if rule not in src:
        lines.append(rule)
if lines and marker in src:
    src = src.replace(marker, "\n".join(lines) + "\n" + marker, 1)
    open(vfile, "w").write(src)
    print("  закрыто:", ", ".join(paths))
else:
    print("  нечего добавлять (уже закрыто или маркер не найден)")
PYEOF
    ok "deny дописаны в права Vosmenog"
  fi
else
  warn "периметр пропущен — закроешь позже в $AGENTS/Vosmenog.md"
fi

# --- 5. go-лаунчер в .bashrc -------------------------------
say "Лаунчер проектов (go)"
BASHRC="$HOME/.bashrc"
if grep -q "agent-os — project launchers" "$BASHRC" 2>/dev/null; then
  warn "go уже в .bashrc — не дублирую"
else
  printf '\n' >> "$BASHRC"
  cat "$VOS/bashrc-snippet.sh" >> "$BASHRC"
  ok "go добавлен в .bashrc (активируй: source ~/.bashrc)"
fi
else
  warn "--harness-only: периметр Восьменога и лаунчер go пропущены"
fi

# --- 5a. Маркеры источника ----------------------------------
#     По ним vosya-update находит клон, а проверка обновлений (update-check.sh) - что уже
#     раскатано. Раньше их писал только update.sh, и сразу после установки обе команды
#     источника не знали.
printf '%s\n' "$SCRIPT_DIR" > "$OC_CONF/.vosmenog-source"
git -C "$SCRIPT_DIR" rev-parse HEAD > "$OC_CONF/.vosmenog-deployed" 2>/dev/null || true
ok ".vosmenog-source / .vosmenog-deployed (откуда раскатано; нужны для vosya-update и проверки обновлений)"

# --- 5b. Автоматическое обновление ---------------------------
say "Автоматическое обновление метода"
echo "  Когда на GitHub выходит релиз, который автор пометил безопасным (решений от вас не требует),"
echo "  метод может обновиться сам, в фоне, на старте сессии. Остальные релизы ставите вы: vosya-update."
echo "  Выключить в любой момент: evm auto off. Без терминала вопрос не задаётся, автообновление остаётся выключенным."
if read -r -p "  Включить автообновление? [Y/n]: " AUTOUP; then
  case "${AUTOUP:-y}" in n|N|no|No|нет|Нет) AUTO_SETUP=off ;; *) AUTO_SETUP=on ;; esac
else
  AUTO_SETUP=off; echo
fi
python3 "$AGENT_OS/bin/evm" auto "$AUTO_SETUP" >/dev/null && ok "автообновление: $AUTO_SETUP (меняется командой evm auto on|off)"

# --- 6. Финал ----------------------------------------------
say "Готово"
if [ "$HARNESS_ONLY" = "1" ]; then
  echo "  Харнесс установлен (без Восьменога). Проверь: evm boot <проект>"
  echo "  Агенту: «Прочитай ~/agent-os/BOOT.md и работай по методу в проекте <ключ>»."
else
  echo "  Проверь режим:"
  echo "    opencode agent list        # должен быть Vosmenog"
  echo "    opencode                   # Tab переключает режимы (build / plan / Vosmenog)"
  echo
  echo "  Дальше — GUIDE.md, раздел «Первый эпик»."
fi
if [ -n "${PERIM:-}" ]; then echo "  Периметр закрыт для: $PERIM"; fi
