#!/usr/bin/env bash
# ============================================================
#  install-windows.sh — установка харнесса ЭВМ под MSYS bash (Git for Windows).
#
#  Зачем отдельный скрипт, если есть setup.sh: на Windows три вещи ломаются молча,
#  и человек видит не ошибку, а «ничего не произошло».
#
#   1. python3. В PATH попадает заглушка Microsoft Store (WindowsApps\python3.exe):
#      печатает слово «Python» и выходит с кодом 49. setup.sh на ней падает.
#      Лечится шимом ~/bin/python3 (кладём перед WindowsApps).
#   2. bash для python. `subprocess.run(["bash", ...])` ищет через CreateProcess,
#      а он смотрит в System32 раньше PATH — находит WSL-овый bash.exe, который
#      не понимает путей C:\... Порог смены и проверка обновлений молчат.
#      Частично лечится патчем в evm (bash_cmd), частично — обёрткой ~/.local/bin/evm.
#   3. git fetch к GitHub. В корпоративной сети SSH до github.com виснет на banner
#      exchange. Монитор обновлений и `evm boot` встают навсегда. Лечится таймаутом
#      в update-check.sh (EVM_FETCH_TIMEOUT, по умолчанию 6 с).
#
#  Запуск (из корня клона репозитория, в MSYS bash — не PowerShell, не WSL):
#      bash windows-config/install-windows.sh            # харнесс (по умолчанию)
#      bash windows-config/install-windows.sh --full     # харнесс + Восьменог (opencode)
#
#  Скрипт идемпотентен: повторный запуск ничего не ломает.
# ============================================================
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Русские скрипты метода печатают «✓» через python. На Windows stdout по умолчанию
# в cp1252 (cp866 в cmd, cp1251 в русской локали), и такой print падает с
# UnicodeEncodeError — установка обрывается на середине. UTF-8-режим обязателен.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
SAY()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
OK()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }
WARN() { printf '\033[1;33m  ! %s\033[0m\n' "$1"; }
ERR()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; }

w() { cygpath -w "$1" 2>/dev/null || printf '%s' "$1"; }

MODE="--harness-only"
[ "${1:-}" = "--full" ] && MODE=""

# --- 0. Где мы вообще ---------------------------------------
case "$(uname -s)" in
  MSYS_NT-*|MINGW*) ;;
  *) ERR "Это не MSYS/ Git-bash. Скрипт для установки под Windows."
     ERR "На Linux/macOS запускайте обычный: ./setup.sh" ; exit 1 ;;
esac
SAY "Среда"
OK "MSYS/Git-bash: $(uname -s)"

# --- 1. python3 без заглушки Store --------------------------
SAY "Проверка python3"
have_py=0
if py -3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' >/dev/null 2>&1; then
  OK "py launcher: $(py -3 -c 'import sys;print(sys.version.split()[0])')"
  have_py=1
elif python -c 'import sys' >/dev/null 2>&1; then
  OK "python: $(python -V 2>&1)"
  have_py=1
fi
if [ "$have_py" = 0 ]; then
  ERR "Не найден рабочий Python. Поставьте: winget install Python.Python.3.12"
  exit 1
fi
# Проверяем именно python3 — обычно это заглушка Store
if ! python3 -c 'print(1)' >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  WARN "python3 в PATH — заглушка Microsoft Store (не работает). Ставлю шим."
fi
mkdir -p "$HOME/bin"
cp "$SRC/windows-config/python3" "$HOME/bin/python3"; chmod +x "$HOME/bin/python3"
# Важно: поднимаем ~/bin и ~/.local/bin В ТЕКУЩЕМ PATH сразу. setup.sh зовёт
# `python3` — если в PATH раньше окажется заглушка Store, он упадёт на середине.
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
hash -r 2>/dev/null || true
case ":$PATH:" in
  *":$HOME/bin:"*) OK "~/bin/python3 (шим) на месте, каталог в PATH" ;;
  *) WARN "~/bin/python3 создан, но ~/bin нет в PATH — добавьте его первым:
       echo 'export PATH=\"\$HOME/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc" ;;
esac
if python3 -c 'print(1)' >/dev/null 2>&1; then
  OK "python3 работает: $(python3 -V 2>&1)"
else
  WARN "python3 всё ещё не работает — откройте НОВОЕ окно терминала и запустите скрипт снова"
fi

# --- 2. jq (нужен хукам Claude Code) ------------------------
SAY "Проверка jq"
if command -v jq >/dev/null 2>&1; then
  OK "jq: $(jq --version 2>&1)"
else
  WARN "jq не найден — хуки Claude Code не соберут JSON для старта сессии."
  WARN "Поставьте: winget install jqlang.jq   (или: scoop install jq)"
fi

# --- 3. Правки ядра под Windows (патч + страховка utf-8) ----
SAY "Правки ядра под Windows (bash_cmd, HOME, таймаут fetch, utf-8)"
# setup.sh раскладывает из установки ИСХОДНИКИ репозитория. Значит, патч нужно
# наложить ДО него — иначе в ~/agent-os/bin/evm не будет bash_cmd(), и «порог
# смены» вместе с проверкой обновлений снова молча пропадут.
PATCHFILE="$SRC/windows-config/windows-fixes.patch"
[[ -f "$PATCHFILE" ]] || PATCHFILE="$(dirname "$SRC")/windows-fixes.patch"
patch_applied=0
if [ -s "$PATCHFILE" ]; then
  PATCH_W="$(cygpath -w "$PATCHFILE")"
  if ( cd "$SRC" && git apply "$PATCH_W" 2>/dev/null ); then
    patch_applied=1
    OK "windows-fixes.patch наложен на исходники (git apply)"
  elif ( cd "$SRC" && patch -p1 --forward --silent -i "$PATCH_W" 2>/dev/null ); then
    patch_applied=1
    OK "windows-fixes.patch наложен на исходники (patch -p1)"
  else
    WARN "патч не накладывается (уже применён или другая версия репозитория)"
    WARN "Ручной путь: cd <исходники> && git apply --reject windows-config/windows-fixes.patch"
  fi
else
  WARN "windows-fixes.patch не найден — правки ядра не применены"
fi
# Страховка по кодировке: даже если патч не лёг (архив без .git),
# переведём python-скрипты в utf-8 — иначе «✓» роняет вывод на cp1252.
GUARD="$SRC/windows-config/utf8-guard.py"
if [ -f "$GUARD" ]; then
  python3 "$(cygpath -w "$GUARD")" "$(cygpath -w "$SRC")" >/dev/null 2>&1 \
    && OK "utf-8-страховка применена к python-скриптам" \
    || WARN "utf8-guard.py не отработал — проверьте кодировку консоли"
fi

# --- 4. Основной установщик --------------------------------
SAY "setup.sh $MODE"
( cd "$SRC" && bash setup.sh ${MODE:+$MODE} < /dev/null ) || {
  ERR "setup.sh завершился с ошибкой — смотрите вывод выше"; exit 1; }

# --- 5. Сверка: правленые файлы в установке ----------------
# На случай, если каталог установки уже существовал и setup.sh файлы не перезаписал.
copy_core() { # $1 — путь в исходниках, $2 — куда в установке
  [ -f "$SRC/$1" ] || return 0
  mkdir -p "$(dirname "$2")" || return 0
  cp "$SRC/$1" "$2" || return 0
  OK "$(basename "$1") → ${2/#$HOME/~}"
}
SAY "Сверка установки с исправленными исходниками"
copy_core harness/tools/evm               "$HOME/agent-os/bin/evm"
copy_core harness/tools/projects-index.py "$HOME/agent-os/bin/projects-index.py"
copy_core harness/connect-server-map.py   "$HOME/agent-os/connect-server-map.py"
copy_core harness/update-check.sh         "$HOME/.config/opencode/memory/update-check.sh"
chmod +x "$HOME/agent-os/bin/evm" "$HOME/agent-os/bin/projects-index.py" 2>/dev/null
if grep -q 'def bash_cmd' "$HOME/agent-os/bin/evm"; then
  OK "проверка: bash_cmd в ~/agent-os/bin/evm есть"
else
  WARN "bash_cmd в установке не найден — «порог смены» будет молчать"
fi
# Маркеры источника. setup.sh зовёт `git -C <MSYS-путь> rev-parse`, а нативный git
# таких путей не понимает и молча оставляет .vosmenog-deployed пустым — из-за этого
# evm status показывает «клон: не найден», а проверка обновлений не знает коммит.
OC_CONF="$HOME/.config/opencode"
if [ -d "$SRC/.git" ] || [ -f "$SRC/.git" ]; then
  printf '%s\n' "$SRC" > "$OC_CONF/.vosmenog-source"
  head_sha="$(git -C "$(cygpath -w "$SRC")" rev-parse HEAD 2>/dev/null)"
  if [ -n "$head_sha" ]; then
    printf '%s\n' "$head_sha" > "$OC_CONF/.vosmenog-deployed"
    OK "маркеры источника: коммит ${head_sha%${head_sha#???????}}… записан"
  else
    WARN "не удалось прочитать HEAD клона — маркер .vosmenog-deployed пуст"
  fi
fi

# --- 6. Обёртка evm ----------------------------------------
SAY "Обёртка evm (MSYS-bash впереди WSL)"
EVM_LINK="$HOME/.local/bin/evm"
mkdir -p "$HOME/.local/bin"
# setup.sh/update.sh кладут сюда КОПИЮ ядра (иногда симлинк) — не обёртку.
# Свой файл узнаём по маркеру, чужой (ядро) — по python-шебангу в первой строке.
# Так детект не зависит от локали и кодировки консоли.
evm_file_kind="none"
if [ -L "$EVM_LINK" ]; then
  evm_file_kind="link"
elif [ -f "$EVM_LINK" ]; then
  if grep -q 'vosmenog-evm-wrapper' "$EVM_LINK" 2>/dev/null; then
    evm_file_kind="wrapper"
  elif head -3 "$EVM_LINK" 2>/dev/null | grep -qi 'python'; then
    evm_file_kind="core-copy"   # копия ядра от setup.sh
  else
    evm_file_kind="foreign"
  fi
fi
if [ "$evm_file_kind" != "foreign" ]; then
  rm -f "$EVM_LINK"
  cp "$SRC/windows-config/evm-wrapper.sh" "$EVM_LINK"; chmod +x "$EVM_LINK"
  OK "~/.local/bin/evm → обёртка (было: $evm_file_kind; ядро остаётся в ~/agent-os/bin/evm)"
else
  WARN "~/.local/bin/evm — посторонний файл, не трогаю. Проверьте вручную."
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) OK "~/.local/bin в PATH" ;;
  *) WARN "~/.local/bin нет в PATH — добавьте:
       echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc" ;;
esac

# --- 7. Маркер онбординга opencode --------------------------
# setup.sh создаёт ~/.config/opencode/.first-run — он запускает онбординг Воси
# при первом входе в opencode. Если opencode не ставится (режим «только харнесс»),
# маркер висит и позже дёргает онбординг при случайном запуске. Убираем.
if ! command -v opencode >/dev/null 2>&1; then
  if [ -f "$HOME/.config/opencode/.first-run" ]; then
    rm -f "$HOME/.config/opencode/.first-run"
    OK "opencode не найден: маркер .first-run убран (онбординг не запустится)"
  fi
fi

# --- 8. Проверка результата --------------------------------
SAY "PATH для новых сессий (~/.bashrc)"
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
if ! grep -q '# --- harness ЭВМ: PATH ---' "$BASHRC"; then
  cat >> "$BASHRC" <<'EOF'

# --- harness ЭВМ: PATH ---
# Шим python3 и обёртка evm. Ставятся первыми: раньше в PATH идёт заглушка
# Microsoft Store (python3) и, при наличии WSL, wsl-овый bash.exe.
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
# --- /harness ЭВМ: PATH ---
EOF
  OK "PATH добавлен в ~/.bashrc (evm будет найден в новом окне)"
else
  OK "PATH уже прописан в ~/.bashrc — не дублирую"
fi

SAY "Проверка"
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
if evm status >/dev/null 2>&1; then
  evm status
else
  ERR "evm не отвечает. Диагностика: bash -x ~/.local/bin/evm status"
  exit 1
fi
echo
if timeout 30 evm boot infra </dev/null 2>/dev/null | grep -q 'порог смены недоступен'; then
  WARN "Порог смены не печатается. Причина — патч bash_cmd на месте?"
  WARN "Проверьте: grep -c bash_cmd ~/agent-os/bin/evm   (должно быть >0)"
elif timeout 30 evm boot infra </dev/null >/dev/null 2>&1; then
  OK "evm boot infra отвечает, порог смены печатается"
fi
if command -v jq >/dev/null 2>&1 && printf '{}' | bash "$HOME/.claude/hooks/session-start.sh" >/dev/null 2>&1; then
  OK "хук SessionStart Claude Code отвечает"
fi

cat <<'EOF'

Дальше:
  1. Откройте НОВОЕ окно терминала (чтобы подхватились PATH и .bashrc).
  2. Проверьте:  evm boot <проект>     (реестр проектов — ~/projects/INDEX.md)
  3. Заполните карту машины: ~/projects/team-work/SERVER.md
  4. Агенту передавайте вход так:
     «Прочитай C:\Users\<вы>\agent-os\BOOT.md и работай по методу в проекте <ключ>»
EOF
