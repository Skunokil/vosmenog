#!/usr/bin/env bash
# Тест постоянного выключателя харнесса (evm off / evm on), EPIC-026, 2026-10-12.
# Работает ТОЛЬКО во временном HOME под /tmp, git не использует вовсе (ни коммитов, ни пушей).
# Запуск: tests/evm-off-test.sh   (код 1 - есть провал)
set -uo pipefail
unset VOSMENOG_PROJECT EVM_ROLE EVM_TOOL
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
case "$T" in /tmp/*|/var/tmp/*) ;; *) echo "FAIL: рабочий каталог вне /tmp: $T"; exit 2;; esac
trap 'rm -rf "$T"' EXIT
fail=0
t() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: ожидалось '$3', получено '$2'"; fail=1; fi; }

H="$T/h"; mkdir -p "$H/.claude" "$H/agent-os/bin" "$H/.config/opencode/memory"
cp "$SRC/harness/tools/evm" "$SRC/harness/tools/evm-threshold" "$SRC/harness/tools/projects-index.py" "$H/agent-os/bin/"; chmod +x "$H/agent-os/bin/"*
cp "$SRC/harness/update-check.sh" "$H/.config/opencode/memory/"
echo "# cc" > "$H/.claude/CLAUDE.md"
mkdir -p "$H/projects/team-work/infra/sessions" && echo "первое дело: проверить" > "$H/projects/team-work/infra/sessions/next-session.md"   # проект без кода для evm boot
printf '%s\n' "$SRC" > "$H/.config/opencode/.vosmenog-source"
EVM() { HOME="$H" python3 "$H/agent-os/bin/evm" "$@"; }
connect() { HOME="$H" python3 "$SRC/harness/connect-server-map.py"; HOME="$H" python3 "$SRC/harness/adapters/claude-code/install.py"; }
connect >/dev/null 2>&1
SETTINGS="$H/.claude/settings.json"; CLAUDEMD="$H/.claude/CLAUDE.md"; FLAG="$H/.config/vosmenog/harness-off"
has_hooks() { grep -c 'session-start.sh\|stop-guard.sh' "$SETTINGS" 2>/dev/null | tr -d ' '; }

echo "== исходное состояние: харнесс включён"
t "в settings.json есть оба хука" "$(has_hooks)" "2"
t "в CLAUDE.md есть импорт карты сервера" "$(grep -c '@.*SERVER.md' "$CLAUDEMD")" "1"
t "status: включён" "$(EVM status | grep -c 'Харнесс: включён')" "1"

echo "== evm off"
EVM off >/dev/null
t "флаг создан" "$([ -e "$FLAG" ] && echo yes)" "yes"
t "status: ВЫКЛЮЧЕН" "$(EVM status | grep -c 'Харнесс: ВЫКЛЮЧЕН')" "1"
t "хук старта Claude Code молчит" "$(printf '{"source":"startup","session_id":"x1"}' | HOME="$H" bash "$H/.claude/hooks/session-start.sh")" ""
t "хук Stop молчит" "$(printf '{"session_id":"x1","cwd":"%s"}' "$H" | HOME="$H" bash "$H/.claude/hooks/stop-guard.sh")" ""
out="$(EVM boot infra)"
t "evm boot печатает одну строку" "$(echo "$out" | wc -l | tr -d ' ')" "1"
t "и в ней сказано «Харнесс выключен»" "$(echo "$out" | grep -c 'Харнесс выключен')" "1"
t "проверка обновлений молчит" "$(HOME="$H" bash "$H/.config/opencode/memory/update-check.sh")" ""
EVM auto on >/dev/null
t "автообновление молчит при выключенном харнессе" "$(EVM auto run --source "$SRC")" ""
t "evm close по явному вызову работает (не отключается)" "$(EVM close infra 2>&1 | grep -c 'evm close\|evm:')" "1"

echo "== установщики не возвращают удалённое, пока выключено"
python3 - "$SETTINGS" <<'P'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["hooks"] = {}; c.pop("statusLine", None); open(p, "w").write(json.dumps(c))
P
grep -v 'SERVER.md' "$CLAUDEMD" > "$CLAUDEMD.new"; mv "$CLAUDEMD.new" "$CLAUDEMD"
out="$(connect 2>&1)"
t "установщик сообщил, что харнесс выключен" "$(echo "$out" | grep -c 'харнесс выключен')" "2"
t "хуки не вернулись" "$(has_hooks)" "0"
t "импорт карты сервера не вернулся" "$(grep -c '@.*SERVER.md' "$CLAUDEMD")" "0"

echo "== evm on"
out="$(EVM on 2>&1)"
t "флаг снят" "$([ ! -e "$FLAG" ] && echo yes)" "yes"
t "хуки вернулись" "$(has_hooks)" "2"
t "импорт карты сервера вернулся" "$(grep -c '@.*SERVER.md' "$CLAUDEMD")" "1"
t "status: включён" "$(EVM status | grep -c 'Харнесс: включён')" "1"
t "evm boot снова работает (не одна строка)" "$([ "$(EVM boot infra 2>&1 | wc -l | tr -d ' ')" -gt 1 ] && echo yes)" "yes"

echo "== установщик заменяет прежние версии хуков, но не правку владельца"
for c in old edited; do
  CH="$T/up-$c"; mkdir -p "$CH/.claude/hooks"
  if [ "$c" = old ]; then
    git -C "$SRC" show f8db652:harness/adapters/claude-code/hooks/session-start.sh > "$CH/.claude/hooks/session-start.sh"
    git -C "$SRC" show e679046:harness/adapters/claude-code/hooks/stop-guard.sh > "$CH/.claude/hooks/stop-guard.sh"
  else
    printf '#!/bin/bash\n# моя правка\n' > "$CH/.claude/hooks/session-start.sh"
    printf '#!/bin/bash\n# моя правка\n' > "$CH/.claude/hooks/stop-guard.sh"
  fi
  HOME="$CH" python3 "$SRC/harness/adapters/claude-code/install.py" >/dev/null 2>&1
done
t "session-start.sh: прежняя версия заменена (есть проверка флага)" "$(grep -c 'harness-off' "$T/up-old/.claude/hooks/session-start.sh")" "1"
t "stop-guard.sh: прежняя версия заменена" "$(grep -c 'harness-off' "$T/up-old/.claude/hooks/stop-guard.sh")" "1"
t "правка владельца в session-start.sh цела" "$(grep -c 'моя правка' "$T/up-edited/.claude/hooks/session-start.sh")" "1"
t "правка владельца в stop-guard.sh цела" "$(grep -c 'моя правка' "$T/up-edited/.claude/hooks/stop-guard.sh")" "1"

echo; [ "$fail" = 0 ] && echo "ВСЕ ТЕСТЫ ЗЕЛЁНЫЕ" || echo "ЕСТЬ ПРОВАЛЫ"; exit "$fail"
