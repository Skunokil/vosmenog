#!/usr/bin/env bash
# Сборка архива харнесса ЭВМ, адаптированного под Windows (MSYS/Git-bash).
#
# Кладёт в ~/dist:  vosmenog-harness-windows-<короткий-sha>.zip  и  .tar.gz
set -euo pipefail

SRC="${1:-$HOME/projects/vosmenog}"
OUT="${2:-$HOME/dist}"
NAME="vosmenog-harness-windows"
# git — нативная программа: MSYS-пути она не понимает, переводим через cygpath
SRC_W="$(cygpath -w "$SRC")"
OUT_W="$(cygpath -w "$OUT" 2>/dev/null || mkdir -p "$OUT" && cygpath -w "$OUT")"
SHA="$(git -C "$SRC_W" rev-parse --short HEAD)"
PKG="$NAME-$SHA"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$OUT" "$STAGE/$PKG"
# исходники без .git и без служебного мусора.
# EPIC.template.md и ONBOARDING.md в корне репозитория — битые симлинки на
# отсутствующий payload/ (артефакт заморозки); tar на Windows их не создаёт,
# а для установки они не нужны — рабочие шаблоны лежат в harness/.
git -C "$SRC_W" archive HEAD -- . ':(exclude)EPIC.template.md' ':(exclude)ONBOARDING.md' \
  | tar -x -C "$STAGE/$PKG"
# незакоммиченная windows-обвязка и патч правок
cp -r "$SRC/windows-config" "$STAGE/$PKG/"
git -C "$SRC_W" diff HEAD > "$STAGE/$PKG/windows-config/windows-fixes.patch" || true
printf '%s\n' "$SHA" > "$STAGE/$PKG/windows-config/BASE-COMMIT.txt"

# короткий README внутри архива
cat > "$STAGE/$PKG/windows-config/README-WINDOWS.txt" <<'EOF'
Харнесс ЭВМ (метод Восьменога) — сборка для Windows.
====================================================

Что это
-------
Рабочая копия репозитория vosmenog с исправлениями, без которых метод на
Windows (MSYS / Git-bash) молча ломается, плюс установщик и обвязка.

Почему отдельная сборка
-----------------------
На Windows три вещи не дают методу работать «из коробки»:

 1. python3. В PATH попадает заглушка Microsoft Store (WindowsApps\python3.exe):
    печатает слово «Python» и выходит с кодом 49. setup.sh на ней падает.
    Лечится шимом ~/bin/python3 (windows-config/python3).

 2. bash для python. `subprocess.run(["bash", ...])` ищет через CreateProcess,
    а тот смотрит в C:\Windows\System32 раньше PATH и находит WSL-овый bash.exe,
    который не понимает путей C:\... В результате «порог смены» и проверка
    обновлений молча пропадают. Лечится патчем bash_cmd() в evm и обёрткой
    ~/.local/bin/evm (windows-config/evm-wrapper.sh).

 3. git fetch к GitHub. В корпоративной сети SSH до github.com виснет на banner
    exchange, и монитор обновлений с `evm boot` встают навсегда. Лечится таймаутом
    в update-check.sh (EVM_FETCH_TIMEOUT, по умолчанию 6 с).

Что внутри
----------
  windows-config/install-windows.sh    установщик: ставит шим, jq-проверку,
                                       запускает setup.sh --harness-only,
                                       ставит обёртку evm, проверяет результат
  windows-config/python3               шим python3 для MSYS bash
  windows-config/evm-wrapper.sh        обёртка ~/.local/bin/evm
  windows-config/windows-fixes.patch   правки к исходникам (git apply)
  windows-config/BASE-COMMIT.txt       коммит, поверх которого сделан патч

Быстрый старт
-------------
  # зависимости (один раз)
  winget install Git.Git Python.Python.3.12 jqlang.jq

  # распаковать архив, затем из его корня в Git-bash:
  bash windows-config/install-windows.sh

  # открыть НОВОЕ окно терминала и проверить
  evm status
  evm boot infra

Подробная инструкция — на странице «Полезная информация» (space DBC).
Полное описание метода — agent-os/METHOD.md в репозитории.
EOF

ZIPPER=""
command -v zip >/dev/null 2>&1 && ZIPPER="zip"
[ -z "$ZIPPER" ] && command -v python3 >/dev/null 2>&1 && ZIPPER="python3"
[ -z "$ZIPPER" ] && command -v py >/dev/null 2>&1 && ZIPPER="py -3"
[ -z "$ZIPPER" ] && command -v powershell >/dev/null 2>&1 && ZIPPER="powershell"
[ -z "$ZIPPER" ] && { echo "нет ни zip, ни python — заархивируйте вручную"; ZIPPER="skip"; }

( cd "$STAGE" && {
    case "$ZIPPER" in
      zip)       zip -qr "$OUT/$PKG.zip" "$PKG" ;;
      python3|py) "$ZIPPER" -c "
import sys, os, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, os.path.dirname(root)))
" "$(cygpath -w "$PKG")" "$(cygpath -w "$OUT/$PKG.zip")" ;;
      powershell) powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$STAGE/$PKG")' -DestinationPath '$(cygpath -w "$OUT/$PKG.zip")' -Force" ;;
    esac
  } && tar -czf "$OUT/$PKG.tar.gz" "$PKG" )
ls -la "$OUT"/"$PKG"* 2>&1
echo "PKG=$PKG"
