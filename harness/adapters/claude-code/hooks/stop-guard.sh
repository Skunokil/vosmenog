#!/usr/bin/env bash
# Stop (Claude Code): сторож конца смены - обёртка над `evm guard stop`.
# Срабатывает после КАЖДОГО ответа агента, поэтому вся логика (один раз за сессию, только
# при устаревшей горячей памяти, тишина на stop_hook_active) внутри evm. Не блокирует.
evm="$(command -v evm 2>/dev/null || true)"
[[ -x "$evm" ]] || evm="$HOME/agent-os/bin/evm"
[[ -x "$evm" ]] || exit 0
exec "$evm" guard stop
