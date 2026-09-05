#!/usr/bin/env bash
# ============================================================
#  Vosmenog — установщик фреймворка дисциплинированного агента
#  Раскладывает payload по местам, сливает конфиг, ставит периметр.
#  Идемпотентен: бэкапит существующее, не клобберит чужой конфиг.
#  Кириллицу НЕ генерирует — только перекладывает готовые файлы payload.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"

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
[ -d "$PAYLOAD" ] || die "Нет папки payload/ рядом со скриптом. Запускай из корня клона."
command -v python3 >/dev/null || die "Нужен python3 (для безопасного слияния конфига)."
if command -v opencode >/dev/null; then
  ok "opencode найден: $(opencode --version 2>/dev/null || echo '?')"
else
  warn "opencode не найден в PATH. Установи его (см. GUIDE, шаг «Установка opencode»),"
  warn "затем запусти setup.sh снова. Файлы разложатся и без него, но проверить режим не выйдет."
fi

# --- 1. Структура папок ------------------------------------
say "Создание структуры"
mkdir -p "$AGENT_OS" "$MEMORY/archive" "$AGENTS" "$OC_CONF/skills"
ok "$AGENT_OS, $MEMORY, $AGENTS"

# --- 2. Раскладка payload ----------------------------------
say "Раскладка файлов фреймворка"
for f in METHOD.md ONBOARDING.md EPIC.template.md TASK.template.md BUG.template.md \
         project-slots.template.md ROADMAP.template.md; do
  if [ -f "$PAYLOAD/$f" ]; then cp "$PAYLOAD/$f" "$AGENT_OS/"; ok "agent-os/$f"; fi
done

PERSONA_FILE="persona_vosya.md"
if [ -f "$PAYLOAD/$PERSONA_FILE" ]; then
  if [ ! -f "$AGENT_OS/$PERSONA_FILE" ]; then
    cp "$PAYLOAD/$PERSONA_FILE" "$AGENT_OS/"
    ok "agent-os/$PERSONA_FILE (установлен)"
  else
    warn "agent-os/$PERSONA_FILE уже есть — не перезаписан. Правь через проект, не в обход."
  fi
fi

cp "$PAYLOAD/agents/Vosmenog.md" "$AGENTS/Vosmenog.md"; ok "agents/Vosmenog.md"

if [ -d "$PAYLOAD/skills" ]; then
  cp -r "$PAYLOAD/skills/." "$OC_CONF/skills/"; ok "skills/ (tutor, infra-bootstrap и др.)"
fi

# --- 2b. Инфраструктурный проект (эталон для скилла infra-bootstrap) ---
# Свежая установка получает заготовку ~/projects/infra + team-work/infra.
# Идемпотентно: существующее не трогаем (владелец мог уже настроить бэкап).
say "Инфраструктурный проект (~/projects/infra)"
INFRA="$HOME/projects/infra"
TEAM_INFRA="$HOME/projects/team-work/infra"
if [ -d "$PAYLOAD/infra-project" ]; then
  if [ ! -d "$INFRA" ]; then
    mkdir -p "$INFRA"
    cp "$PAYLOAD/infra-project/"*.sh \
       "$PAYLOAD/infra-project/.env.example" \
       "$PAYLOAD/infra-project/.gitignore" \
       "$PAYLOAD/infra-project/AGENTS.md" \
       "$PAYLOAD/infra-project/RESTORE.md" \
       "$PAYLOAD/infra-project/ROADMAP.md" "$INFRA/"
    chmod +x "$INFRA/"*.sh
    ok "infra/ развёрнут (скрипты, шаблоны). Креды добавит владелец в .env"
  else
    warn "~/projects/infra уже есть — не трогаю"
  fi
  if [ ! -d "$TEAM_INFRA" ]; then
    mkdir -p "$TEAM_INFRA/epics" "$TEAM_INFRA/backlog" "$TEAM_INFRA/sessions"
    cp "$PAYLOAD/infra-project/epics/EPIC-001-backup.md" "$TEAM_INFRA/epics/"
    cp "$PAYLOAD/infra-project/backlog/"*.md "$TEAM_INFRA/backlog/"
    printf '# Journal — Infra\n' > "$TEAM_INFRA/sessions/journal.md"
    sed 's/<проект>/infra/' "$PAYLOAD/next-session.template.md" > "$TEAM_INFRA/sessions/next-session.md"
    ok "team-work/infra/ развёрнут (EPIC-001-backup эталон, backlog, journal)"
  else
    warn "~/projects/team-work/infra уже есть — не трогаю"
  fi
fi

# --- 2c. Кит головы (файлы для веб-Клода / Минотавра) ------
if [ -d "$PAYLOAD/shared/skills" ]; then
  mkdir -p "$AGENT_OS/head-kit"
  cp "$PAYLOAD/shared/skills/"*.md "$AGENT_OS/head-kit/"; ok "agent-os/head-kit/ (session_start, персона, workflow, правила)"
fi

cp "$PAYLOAD/STARTUP.md" "$MEMORY/STARTUP.md"; ok "memory/STARTUP.md"
cp "$PAYLOAD/next-session.template.md" "$MEMORY/next-session.template.md"; ok "memory/next-session.template.md"
cp "$PAYLOAD/AGENTS.md" "$OC_CONF/AGENTS.md"; ok "AGENTS.md (глобальный слот инструкций)"
if [ ! -f "$MEMORY/journal.md" ]; then
  printf '# Journal — Session Log\n' > "$MEMORY/journal.md"; ok "memory/journal.md (создан)"
else
  warn "memory/journal.md уже есть — не трогаю (память сохранена)"
fi
# user-profile.md — журнальный паттерн (есть? → не трогаю)
if [ ! -f "$MEMORY/user-profile.md" ]; then
  cp "$PAYLOAD/user-profile.template.md" "$MEMORY/user-profile.md"; ok "memory/user-profile.md (создан)"
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
say "Конфиг opencode.json (instructions[])"
CONF_FILE="$OC_CONF/opencode.json"
if [ -f "$CONF_FILE" ]; then
  cp "$CONF_FILE" "$CONF_FILE.bak-$(date +%F-%H%M%S)"; ok "бэкап существующего конфига"
fi
python3 - "$CONF_FILE" "$PAYLOAD/opencode.json" << 'PYEOF'
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

# --- 4. Периметр (барьер прав Vosmenog) --------------------
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
  cat "$PAYLOAD/bashrc-snippet.sh" >> "$BASHRC"
  ok "go добавлен в .bashrc (активируй: source ~/.bashrc)"
fi

# --- 6. Финал ----------------------------------------------
say "Готово"
echo "  Проверь режим:"
echo "    opencode agent list        # должен быть Vosmenog"
echo "    opencode                   # Tab переключает режимы (build / plan / Vosmenog)"
echo
echo "  Дальше — GUIDE.md, раздел «Первый эпик»."
if [ -n "${PERIM:-}" ]; then echo "  Периметр закрыт для: $PERIM"; fi
