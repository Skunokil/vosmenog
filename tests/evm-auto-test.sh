#!/usr/bin/env bash
# Тест автообновления (EPIC-026, 2026-10-12): ученик + origin + релизы. Самый важный класс проверок -
# где автообновление НЕ должно срабатывать. Запуск: tests/evm-auto-test.sh (код 1 - есть провал).
set -uo pipefail
unset VOSMENOG_PROJECT EVM_ROLE
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git clone -q --bare "$SRC" "$T/origin.git" 2>/dev/null                 # только закоммиченное состояние репозитория
BR=main
fail=0
t() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: ожидалось '$3', получено '$2'"; fail=1; fi; }

# env <имя> <режим on|off>: чистый HOME, ученик клонирует origin и ставит
env_new() {
  E="$T/$1"; H="$E/h"; mkdir -p "$H/.claude"; echo "# cc" > "$H/.claude/CLAUDE.md"
  git clone -q "$T/origin.git" "$E/work" 2>/dev/null
  HOME="$H" PATH="$H/.local/bin:$PATH" bash "$E/work/setup.sh" </dev/null >"$E/setup.out" 2>&1
  HOME="$H" python3 "$H/agent-os/bin/evm" auto "$2" >/dev/null
  D="$(cat "$H/.config/opencode/.vosmenog-deployed")"
}
# release <yes|no|nochangelog>: dev-клон выпускает релиз во ВРЕМЕННЫЙ origin.
# ЗАЩИТА (после случая 12.10, когда сбой cd отправил тестовый коммит в настоящий GitHub):
# работаем только через git -C "$T/dev", пишем только по абсолютным путям внутри $T,
# пушим только в абсолютный путь "$T/origin.git" - слово «origin» как имя remote здесь не используется.
release() {
  rm -rf "$T/dev"; git clone -q "$T/origin.git" "$T/dev" 2>/dev/null
  [ -d "$T/dev/.git" ] || { echo "  FAIL фикстура: нет $T/dev"; fail=1; return 1; }
  case "$T" in /tmp/*|/var/tmp/*) ;; *) echo "  FAIL фикстура: рабочий каталог вне /tmp"; fail=1; return 1;; esac
  case "$1" in
    yes|no) python3 "$SRC/tests/release-entry.py" "$1" "$T/dev/CHANGELOG.md" "$RANDOM$RANDOM" ;;
  esac
  echo "$RANDOM" >> "$T/dev/harness/BOOT.md"
  git -C "$T/dev" -c user.email=t@t -c user.name=t commit -qam "релиз $1" \
    && git -C "$T/dev" push -q "$T/origin.git" "HEAD:$BR" 2>/dev/null
}
check() { HOME="$H" bash "$H/.config/opencode/memory/update-check.sh" 2>&1; }
deployed() { cat "$H/.config/opencode/.vosmenog-deployed"; }
wait_deploy() { for _ in $(seq 1 40); do [ "$(deployed)" != "$D" ] && return 0; sleep 1; done; return 1; }

echo "== S1: выключено + безопасный релиз -> не накатывается"
env_new s1 off; release yes; out="$(check)"
t "видно обычное уведомление" "$(echo "$out" | grep -c 'Вышло обновление')" "1"
t "автоматика молчит" "$(echo "$out" | grep -c 'Автообновление')" "0"; sleep 3
t "версия не изменилась" "$([ "$(deployed)" = "$D" ] && echo same)" "same"

echo "== S2: включено + безопасный релиз -> накатывается само"
env_new s2 on; release yes; out="$(check)"
t "сказано, что накатывает в фоне" "$(echo "$out" | grep -c 'накатываю в фоне')" "1"
wait_deploy; t "версия сменилась на свежую" "$([ "$(deployed)" = "$(git -C "$T/origin.git" rev-parse "$BR")" ] && echo fresh)" "fresh"
t "журнал содержит метку автозапуска (update.sh после pull перезапускается, метка может быть дважды)" "$([ "$(grep -c 'автоматический запуск' "$H/.local/state/evm/auto-update.log")" -ge 1 ] && echo yes)" "yes"
t "в установке появился новый BOOT.md" "$(cmp -s "$E/work/harness/BOOT.md" "$H/agent-os/BOOT.md" && echo same)" "same"
t "следующий старт: «Метод обновился»" "$(check | grep -c 'Метод обновился')" "1"
t "и дальше тишина" "$(check)" ""

echo "== S3: включено + релиз БЕЗ пометки -> вручную, с причиной"
env_new s3 on; release no; out="$(check)"
t "названа причина" "$(echo "$out" | grep -c 'нужно накатить вручную: автор релиза не пометил')" "1"; sleep 3
t "версия не изменилась" "$([ "$(deployed)" = "$D" ] && echo same)" "same"

echo "== S4: включено + безопасный релиз, но в клоне свои правки -> вручную"
env_new s4 on; echo "моя правка" >> "$E/work/harness/BOOT.md"; release yes
git -C "$E/work" fetch -q 2>/dev/null; out="$(check)"
t "названа причина про правки" "$(echo "$out" | grep -c 'нужно накатить вручную: в клоне есть незакоммиченные правки')" "1"; sleep 3
t "версия не изменилась" "$([ "$(deployed)" = "$D" ] && echo same)" "same"

echo "== S5: включено + безопасный релиз, но недавно уже пробовали -> ждёт"
env_new s5 on; release yes; mkdir -p "$H/.local/state/evm"; touch "$H/.local/state/evm/auto-update.last"; out="$(check)"
t "не запущено" "$(echo "$out" | grep -c 'накатываю в фоне')" "0"; sleep 3
t "версия не изменилась" "$([ "$(deployed)" = "$D" ] && echo same)" "same"

echo "== S6: релиз без записи в CHANGELOG -> вручную"
env_new s6 on; release nochangelog; out="$(check)"
t "названа причина" "$(echo "$out" | grep -c 'нет новой записи в CHANGELOG')" "1"

echo "== S7: команды включения и выключения"
env_new s7 off
t "status: выключено" "$(HOME="$H" python3 "$H/agent-os/bin/evm" auto status | grep -c 'выключено')" "1"
HOME="$H" python3 "$H/agent-os/bin/evm" auto on >/dev/null
t "on -> ВКЛЮЧЕНО" "$(HOME="$H" python3 "$H/agent-os/bin/evm" auto status | grep -c 'ВКЛЮЧЕНО')" "1"
HOME="$H" python3 "$H/agent-os/bin/evm" auto off >/dev/null
t "off -> выключено" "$(HOME="$H" python3 "$H/agent-os/bin/evm" auto status | grep -c 'выключено')" "1"

echo "== S8: уведомление «Метод обновился» у каждого инструмента своё"
env_new s8 off
claude_check() { EVM_TOOL=claude HOME="$H" bash "$H/.config/opencode/memory/update-check.sh" 2>&1; }
check >/dev/null; claude_check >/dev/null          # после установки оба инструмента хоть раз стартовали: отметки созданы
release yes
HOME="$H" PATH="$H/.local/bin:$PATH" bash "$E/work/update.sh" </dev/null >/dev/null 2>&1       # владелец обновился вручную
t "Claude Code: первый старт - рассказывает" "$(claude_check | grep -c 'Метод обновился')" "1"
t "Claude Code: второй старт - тишина" "$(claude_check)" ""
t "opencode (прочие): всё ещё рассказывает, отметка у него своя" "$(check | grep -c 'Метод обновился')" "1"
t "opencode: второй старт - тишина" "$(check)" ""

echo "== S9: установщик заменяет прежнюю версию хука-обёртки Claude Code, но не правку владельца"
for case in old edited; do
  CH="$T/s9-$case"; mkdir -p "$CH/.claude/hooks"
  if [ "$case" = old ]; then git -C "$SRC" show e679046:harness/adapters/claude-code/hooks/session-start.sh > "$CH/.claude/hooks/session-start.sh"
  else printf '#!/bin/bash\n# моя правка\n' > "$CH/.claude/hooks/session-start.sh"; fi
  HOME="$CH" python3 "$SRC/harness/adapters/claude-code/install.py" >/dev/null 2>&1
done
t "прежняя версия -> заменена на новую (с меткой EVM_TOOL)" "$(grep -c 'EVM_TOOL=claude' "$T/s9-old/.claude/hooks/session-start.sh")" "1"
t "правка владельца не тронута" "$(grep -c 'моя правка' "$T/s9-edited/.claude/hooks/session-start.sh")" "1"

echo; [ "$fail" = 0 ] && echo "ВСЕ ТЕСТЫ ЗЕЛЁНЫЕ" || echo "ЕСТЬ ПРОВАЛЫ"; exit "$fail"
