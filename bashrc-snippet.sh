# ============================================================
#  agent-os — project launchers + обновление Vosmenog
#  Вставляется в ~/.bashrc. Перезагрузить: source ~/.bashrc
# ============================================================

# --- Путь к клону репо Vosmenog (поправь, если клонировал в другое место) ---
VOSMENOG_REPO="$HOME/vosmenog"

# --- Проверка обновлений (тихо, не чаще раза в сутки) ---
# Только УВЕДОМЛЯЕТ. Накат — вручную командой vosya-update.
_vosya_check_update() {
  [ -d "$VOSMENOG_REPO/.git" ] || return 0
  local stamp="$HOME/.config/opencode/.vosya-update-check"
  local now last
  now=$(date +%s)
  if [ -f "$stamp" ]; then
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    [ $((now - last)) -lt 86400 ] && return 0   # уже проверяли сегодня
  fi
  echo "$now" > "$stamp"
  ( cd "$VOSMENOG_REPO" 2>/dev/null || exit 0
    git fetch -q 2>/dev/null || exit 0
    local l r
    l=$(git rev-parse @ 2>/dev/null) || exit 0
    r=$(git rev-parse '@{u}' 2>/dev/null) || exit 0
    if [ -n "$r" ] && [ "$l" != "$r" ]; then
      printf '\033[1;33m  ! Вышло обновление Vosmenog. Накати метод: vosya-update\033[0m\n'
    fi
  )
}

# --- Накат метод-контента вручную (безопасный, не трогает права/конфиг) ---
vosya-update() {
  ( cd "$VOSMENOG_REPO" && ./update.sh )
}

# --- go <proj> — зайти в проект и запустить opencode там ---
# Добавляй свои проекты в case. Первой строкой — проверка обновлений.
go() {
  _vosya_check_update
  case "$1" in
    # myproj) cd ~/path/to/myproj && opencode ;;
    "" ) echo "go: укажи проект"; return 1 ;;
    *  ) echo "go: неизвестный проект '$1'. Добавь его в case в ~/.bashrc"; return 1 ;;
  esac
}
