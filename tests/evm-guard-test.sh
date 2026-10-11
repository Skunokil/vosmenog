#!/usr/bin/env bash
# Тест сторожей evm на фикстуре (EPIC-026 Ф5, AC 4 и 5). Свой HOME во временном каталоге,
# время файлов подменяется touch -d. Запуск: tests/evm-guard-test.sh  (код 1 - есть провал).
set -uo pipefail
unset VOSMENOG_PROJECT EVM_ROLE EVM_STALE_MIN   # окружение сессии не должно перекрывать фикстуру
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$(mktemp -d)"; trap 'rm -rf "$F"' EXIT
fail=0
t() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: ожидалось '$3', получено '$2'"; fail=1; fi; }

mkdir -p "$F/projects/demo" "$F/projects/team-work/demo/sessions" "$F/.local/state/evm" "$F/agent-os/bin"
cp "$SRC/harness/tools/evm" "$SRC/harness/tools/evm-threshold" "$SRC/harness/tools/projects-index.py" "$F/agent-os/bin/"
chmod +x "$F/agent-os/bin/"*
g() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
OLD="$(date -d '3 days ago' '+%Y-%m-%dT%H:%M:%S')"       # начальные коммиты - задолго до сессии
export GIT_AUTHOR_DATE="$OLD" GIT_COMMITTER_DATE="$OLD"
( cd "$F/projects/demo" && git init -q && printf '<!-- passport\nkey: demo\nplanning: team-work/demo\nstatus: active\n-->\n# demo\n' > AGENTS.md && git add . && g . commit -q -m init )
( cd "$F/projects/team-work" && git init -q && echo "# mem. HEAD самодостаточен" > demo/sessions/next-session.md \
  && echo "$(date +%F) [мин] старт" > demo/sessions/journal.md && g . add . && g . commit -q -m init )
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
now=$(date +%s)
MEM="$F/projects/team-work/demo/sessions/next-session.md"
touch -d "@$((now-7200))" "$MEM"                       # память двухчасовой давности
guard() { printf '%s' "$1" | HOME="$F" python3 "$F/agent-os/bin/evm" guard stop; }
close() { HOME="$F" VOSMENOG_PROJECT=demo python3 "$F/agent-os/bin/evm" close demo >/dev/null; echo $?; }
mk_start() { : > "$F/.local/state/evm/start-$1"; touch -d "@$2" "$F/.local/state/evm/start-$1"; }
J() { echo "{\"session_id\":\"$1\",\"cwd\":\"$F/projects/demo\"${2:-}}"; }

echo "== сторож Stop"
mk_start A $((now-3600))
t "нет изменений за сессию - тишина" "$(guard "$(J A)")" ""
( cd "$F/projects/demo" && echo 1 > f.txt && git add . && g . commit -q -m work )   # работа: коммит сейчас
out="$(guard "$(J A)")"
t "работа без обновления памяти - напоминание" "$(echo "$out" | grep -c additionalContext)" "1"
t "напоминание - валидный JSON с systemMessage" "$(echo "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("systemMessage" in d)')" "True"
t "второй вызов в той же сессии - тишина (ровно одно)" "$(guard "$(J A)")" ""
mk_start B $((now-3600))
t "stop_hook_active=true - тишина" "$(guard "$(J B ',"stop_hook_active":true')")" ""
t "субагент (agent_id) - тишина" "$(guard "$(J B ',"agent_id":"x"')")" ""
t "без session_id - тишина" "$(guard '{"cwd":"'"$F"'/projects/demo"}')" ""
t "каталог вне проекта - тишина" "$(guard '{"session_id":"C","cwd":"/tmp"}')" ""
touch "$MEM"                                           # память обновлена
mk_start D $((now-3600))
t "после обновления памяти - тишина" "$(guard "$(J D)")" ""

echo "== evm close"
touch -d "@$((now-7200))" "$MEM"
t "память старше работы - красный (код 1)" "$(close)" "1"
touch "$MEM"; printf '%s [мин] итог\n' "$(date +%F)" >> "$F/projects/team-work/demo/sessions/journal.md"
t "память свежая, строка журнала есть - зелёный (код 0)" "$(close)" "0"
before="$(cd "$F" && find . -type f ! -path './.local/*' ! -path '*/.git/*' | sort | xargs md5sum | md5sum)"
close >/dev/null
after="$(cd "$F" && find . -type f ! -path './.local/*' ! -path '*/.git/*' | sort | xargs md5sum | md5sum)"
t "evm close ничего не пишет (хеши до/после)" "$before" "$after"

[ "$fail" = 0 ] && echo "ВСЕ ТЕСТЫ ЗЕЛЁНЫЕ" || echo "ЕСТЬ ПРОВАЛЫ"
exit "$fail"
