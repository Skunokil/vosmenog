#!/usr/bin/env bash
# ============================================================
#  memory-guard — сторож бюджета памяти смены (EPIC-019, Э5)
#
#  Смотрит на ДОКУМЕНТЫ, а не на поведение агента: чинить надо файл.
#  Уложились в пороги — молчит (не шуметь). Вылезли — одна строка на
#  находку: какой документ распух и на сколько.
#
#  Меряет знаки (wc -m), а не строки и не токены: строка бывает и в
#  20 знаков, и в 3 000, а токены локально не посчитать. Мерь ту
#  величину, которой платишь.
#
#  Использование:
#    memory-guard.sh <project>   # ~/projects/team-work/<project>/sessions
#    memory-guard.sh             # общая память ~/.config/opencode/memory
# ============================================================
set -uo pipefail

MAX_HOT=4000       # next-session.md — горячий документ, читается всегда
MAX_JOURNAL=15000  # journal.md — индекс; больше → хвост в archive/journal-<год>.md
MAX_BOOT=36000     # весь старт смены: инвариант METHOD — не больше 25 000 токенов,
                   # что при 1,3–1,6 знака на токен даёт ~36 000 знаков. Считаем
                   # знаки: их видно wc -m, токены локально не посчитать.
MAX_LINE=200       # одна запись журнала
RULE_DATE=2026-09-05  # с этой даты действует порог записи (EPIC-019, Э1).
                      # Записи старше — история: по решению Р3 её не переписывают,
                      # а сторож, который шумит на легаси каждую смену, будет
                      # выключен и перестанет ловить настоящее.

if [ $# -ge 1 ] && [ -n "${1:-}" ]; then
  DIR="$HOME/projects/team-work/$1/sessions"
else
  DIR="$HOME/.config/opencode/memory"
fi

[ -d "$DIR" ] || exit 0
found=0
say() { printf '  ! %s\n' "$1"; found=1; }

HOT="$DIR/next-session.md"
JOURNAL="$DIR/journal.md"

if [ -f "$HOT" ]; then
  n=$(wc -m < "$HOT")
  [ "$n" -gt "$MAX_HOT" ] && say "next-session.md — $n знаков при потолке $MAX_HOT: сжать до первого дела и открытых вопросов, подробности в эпик."
else
  say "next-session.md отсутствует — горячей памяти нет, старт смены не на что опереть (шаблон: ~/.config/opencode/memory/next-session.template.md)."
fi

if [ -f "$JOURNAL" ]; then
  n=$(wc -m < "$JOURNAL")
  [ "$n" -gt "$MAX_JOURNAL" ] && say "journal.md — $n знаков при потолке $MAX_JOURNAL: увести целиком в archive/journal-$(date +%Y).md и начать новый."
  # длину проверяем только у записей, сделанных после введения правила:
  # строка журнала начинается с даты в ISO, поэтому сравнение — строковое.
  long=$(awk -v m="$MAX_LINE" -v d="$RULE_DATE" \
    'match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) && substr($0,1,10) >= d && length($0) > m {c++} END {print c+0}' "$JOURNAL")
  [ "$long" -gt 0 ] && say "journal.md — свежих записей длиннее $MAX_LINE знаков: $long. Подробность идёт в archive/, журнал её не повторяет."
fi

# бюджет старта целиком: сумма того, что читается всегда. Инвариант меряет
# СТАРТ, а не отдельный файл — иначе распухнет тот документ, за которым никто
# не следит (так журнал и вырос под правилом «≤ 100 строк»).
BOOT_FILES=(
  "$HOME/.config/opencode/memory/STARTUP.md"
  "$HOME/agent-os/METHOD.md"
  "$HOME/agent-os/persona_vosya.md"
  "$HOME/.config/opencode/AGENTS.md"
  "$HOT"
)
# проектные слоты берём там же, где их берёт opencode: в текущем каталоге и
# выше по дереву, до $HOME. Имя каталога проекта не всегда совпадает с именем
# в team-work, поэтому по имени не гадаем.
d="$PWD"
while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
  if [ -f "$d/AGENTS.md" ]; then BOOT_FILES+=("$d/AGENTS.md"); break
  elif [ -f "$d/CLAUDE.md" ]; then BOOT_FILES+=("$d/CLAUDE.md"); break
  fi
  d="$(dirname "$d")"
done
boot=0
for f in "${BOOT_FILES[@]}"; do
  [ -f "$f" ] || continue
  boot=$(( boot + $(wc -m < "$f") ))
done
if [ "$boot" -gt "$MAX_BOOT" ]; then
  say "бюджет старта — $boot знаков при потолке $MAX_BOOT (~25 000 токенов). Крупнейшие:"
  for f in "${BOOT_FILES[@]}"; do
    [ -f "$f" ] && printf '%8d  %s\n' "$(wc -m < "$f")" "${f/#$HOME/~}"
  done | sort -rn | head -3 | sed 's/^/      /'
fi

[ "$found" -eq 1 ] && printf '  (сторож памяти: EPIC-019, METHOD → «Память смены»)\n'
exit 0
