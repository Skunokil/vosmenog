# ============================================================
#  agent-os — project launchers
#  Вставляется в ~/.bashrc. Перезагрузить: source ~/.bashrc
# ============================================================
#
#  go <proj> — зайти в проект и запустить opencode там.
#  Ставит метку VOSMENOG_PROJECT — сценарии памяти/эпиков сами
#  находят ~/projects/team-work/$VOSMENOG_PROJECT. cd в папку проекта
#  обязателен: opencode авто-подхватывает <проект>/AGENTS.md
#  (слоты) только из папки проекта.
#
#  Добавляй свои проекты в case ниже. Пример-заглушка — замени.
# ------------------------------------------------------------
go() {
  case "$1" in
    # myproj) export VOSMENOG_PROJECT="myproj"; cd ~/path/to/myproj && opencode ;;
    "" )  echo "go: укажи проект. Доступно: $(declare -f go | grep -oP '(?<=    )\w+(?=\))' | grep -v '^$' | tr '\n' ' ')" ; return 1 ;;
    *  )  echo "go: неизвестный проект '$1'. Добавь его в case в ~/.bashrc" ; return 1 ;;
  esac
}


# ------------------------------------------------------------
#  vosya-new-project <name> — развернуть team-work-болванку под новый проект.
#  Скелет папок проекта + кросс-проектный shared/ (один раз),
#  шаблоны и кит головы в shared/. Идемпотентен.
# ------------------------------------------------------------
vosya-new-project() {
  local name="$1"
  [ -n "$name" ] || { echo "vosya-new-project: укажи имя проекта"; return 1; }
  local tw="$HOME/projects/team-work/$name"
  [ -d "$tw" ] && { echo "team-work/$name уже есть — не трогаю"; return 1; }
  mkdir -p "$tw"/{epics,bugs,backlog,sessions/archive,exchange/incoming,exchange/outgoing,exchange/archive,archive}
  echo "# Journal — $name" > "$tw/sessions/journal.md"
  local sh="$HOME/projects/team-work/shared"
  mkdir -p "$sh/skills" "$sh/templates"
  for t in EPIC TASK BUG; do
    [ -f "$sh/templates/$t.template.md" ] || cp "$HOME/agent-os/$t.template.md" "$sh/templates/" 2>/dev/null
  done
  if [ -d "$HOME/agent-os/head-kit" ]; then
    cp "$HOME/agent-os/head-kit/"*.md "$sh/skills/" 2>/dev/null
  fi
  echo "✓ team-work/$name готов · shared/{skills,templates} на месте · метка: go $name"
}
