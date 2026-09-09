#!/usr/bin/env bash
# ============================================================
#  update-check.sh — сторож обновлений метода.
#  Печатает ТОЛЬКО когда есть что сказать: молчание = всё показано
#  и всё раскатано. Ничего не меняет, кроме отметки «показано».
#
#  Зачем скриптом, а не правилом в протоколе: правило без проверки —
#  пожелание. Ритуал, который агент выполняет по памяти, выполняется
#  наполовину (проверено на живом: раздел Б сделан, раздел А забыт).
# ============================================================
set -uo pipefail

OC_CONF="$HOME/.config/opencode"
MEMORY="$OC_CONF/memory"
SEEN_FILE="$MEMORY/.vosmenog-changelog-seen"

SRC="$(cat "$OC_CONF/.vosmenog-source" 2>/dev/null || true)"
DEPLOYED="$(cat "$OC_CONF/.vosmenog-deployed" 2>/dev/null || true)"

# нет маркера, путь протух, не git-репо — это нормальное состояние
# установки без исходников: молчим.
[ -n "$SRC" ] && [ -d "$SRC" ] || exit 0
git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# --- А. раскатано, но ещё не показано ------------------------
if [ -n "$DEPLOYED" ]; then
  SEEN="$(cat "$SEEN_FILE" 2>/dev/null || true)"
  if [ -z "$SEEN" ]; then
    # первый запуск механизма: запомнить и не вываливать всю историю
    printf '%s\n' "$DEPLOYED" > "$SEEN_FILE"
  elif [ "$SEEN" != "$DEPLOYED" ]; then
    if git -C "$SRC" cat-file -e "$SEEN^{commit}" 2>/dev/null; then
      echo "Метод обновился, вот что нового:"
      git -C "$SRC" log --oneline "$SEEN..$DEPLOYED" | sed 's/^/  /'
      echo "  файлы:"
      git -C "$SRC" diff --name-only "$SEEN..$DEPLOYED" | sed 's/^/    /'
    fi
    printf '%s\n' "$DEPLOYED" > "$SEEN_FILE"
  fi
fi

# --- Б. есть в репозитории, но не раскатано ------------------
if git -C "$SRC" fetch --quiet origin main 2>/dev/null; then
  BASE="${DEPLOYED:-HEAD}"
  N="$(git -C "$SRC" rev-list --count "$BASE..origin/main" 2>/dev/null || echo 0)"
  if [ "${N:-0}" -gt 0 ]; then
    echo "Вышло обновление Vosmenog ($N коммит(ов)) — не раскатано. Накати: $SRC/update.sh"
    git -C "$SRC" log --oneline "$BASE..origin/main" 2>/dev/null | sed 's/^/  /'
  fi
fi

# --- В. правка застряла в источнике --------------------------
DIRTY="$(git -C "$SRC" status --porcelain --untracked-files=no 2>/dev/null || true)"
if [ -n "$DIRTY" ]; then
  echo "В источнике есть незакоммиченные правки — на машину раскатаются, в репозиторий не уедут:"
  printf '%s\n' "$DIRTY" | sed 's/^/  /'
fi

exit 0
