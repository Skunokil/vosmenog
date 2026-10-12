#!/usr/bin/env bash
# Stop (Claude Code): сторож конца смены - обёртка над `evm guard stop`.
# Срабатывает после КАЖДОГО ответа агента, поэтому вся логика (один раз за сессию, только
# при устаревшей горячей памяти, тишина на stop_hook_active) внутри evm. Не блокирует.
# Постоянный выключатель харнесса (evm off): флаг-файл. Есть флаг - хук молчит и ничего не делает.
[[ -e "$HOME/.config/vosmenog/harness-off" ]] && exit 0
evm="$(command -v evm 2>/dev/null || true)"
[[ -x "$evm" ]] || evm="$HOME/agent-os/bin/evm"
[[ -x "$evm" ]] || exit 0
exec "$evm" guard stop
