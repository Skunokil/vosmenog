#!/usr/bin/env bash
# SessionStart (Claude Code): порядок чтения и обстановка на входе - тонкая обёртка над evm.
#
# С 2026-10-11 (EPIC-026 Ф5) логика порога смены живёт в харнессе (`evm threshold`), а сам
# хук лишь вызывает `evm boot`: раньше агент должен был помнить его запустить. Хук получает
# JSON со stdin; поле source решает, сколько показывать:
#   startup, clear, compact - полный вывод (после сжатия контекст возвращается целиком);
#   resume, fork            - краткий (контекст на месте, нужна только смена и обстановка).
# Проект берётся из $VOSMENOG_PROJECT или каталога сессии; не определился - остаётся порог.
set -uo pipefail

in="$(cat 2>/dev/null || true)"
src="$(jq -r '.source // "startup"' <<<"$in" 2>/dev/null || echo startup)"
sid="$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null || true)"

# Метка начала сессии нужна сторожу Stop. Возобновление и сжатие её не двигают.
if [[ -n "$sid" ]]; then
  mkdir -p "$HOME/.local/state/evm" 2>/dev/null || true
  f="$HOME/.local/state/evm/start-$sid"
  case "$src" in startup|clear) : > "$f" ;; *) [[ -e "$f" ]] || : > "$f" ;; esac
fi

evm="$(command -v evm 2>/dev/null || true)"
[[ -x "$evm" ]] || evm="$HOME/agent-os/bin/evm"
[[ -x "$evm" ]] || exit 0                       # установки харнесса нет - молчим

case "$src" in resume|fork) flags=(--brief) ;; *) flags=() ;; esac
if ! "$evm" boot "${flags[@]}" 2>/dev/null; then
  "$evm" threshold 2>/dev/null                   # проект не определился - хотя бы порог
fi
exit 0
