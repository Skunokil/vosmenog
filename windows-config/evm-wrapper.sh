#!/usr/bin/env bash
# Локальная обёртка вокруг установленного evm (agent-os/bin/evm) для MSYS bash на Windows.
#
# Зачем: python на Windows ищет `bash` через CreateProcess, а тот смотрит в System32
# раньше PATH и находит WSL-овый bash.exe. WSL не понимает путей C:\... — порог смены
# и проверка обновлений молча пропадали. Обёртка ставит MSYS-bash первым в PATH.
#
# Второй повод: `evm` нужно передать настоящий python3 (~/bin/python3), иначе он
# запустится заглушкой WindowsApps.
#
# Живёт в ~/.local/bin/evm обычным файлом (не симлинком): setup.sh/update.sh симлинк
# пересоздают, а посторонний файл не трогают — значит обёртка переживёт обновление.
# Обновляемое ядро — по-прежнему ~/agent-os/bin/evm, править его не надо.
set -uo pipefail
# Метка для установщика: по ней он узнаёт свою обёртку и не боится перезаписать.
# vosmenog-evm-wrapper

b="$(command -v bash || true)"
if [ -z "$b" ]; then
  echo "evm: bash не найден в PATH" >&2
  exit 1
fi
bwin="$(cygpath -w "$b" 2>/dev/null | sed 's#[\\/][^\\/]*$##' || true)"
export PATH="${bwin:-$(dirname "$b")}:$PATH"

PY="$HOME/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3 || command -v python)"
# UTF-8 для вывода: скрипты метода печатают «✓» и русский текст, а нативный
# python на Windows по умолчанию берёт cp1252/cp866 и падает с UnicodeEncodeError.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
exec "$PY" "$HOME/agent-os/bin/evm" "$@"
