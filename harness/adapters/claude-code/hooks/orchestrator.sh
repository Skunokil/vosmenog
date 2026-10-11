#!/usr/bin/env bash
# ОРКЕСТРАТОР — кто сводит работу, когда сессий больше одной.
#
# Заведён 2026-09-12 по решению владельца. Повод: в дереве Detective-OS за
# сутки столкнулись три сессии (пять раз), а вечером сессия, собиравшая релиз,
# встала перед тегом — она не могла знать, самодостаточна ли чужая работа в
# HEAD. Вопрос был задан не тому агенту и стоил бы выката середины чужого
# эпика, если бы она не остановилась.
#
# Оркестратор — НЕ начальник и не обязательная фигура. Это роль «одно окно»:
# сводит релизы, держит карту областей, отвечает на «можно ли катить». Нужен
# ровно тогда, когда сессий больше одной. В одиночку согласовывать не с кем,
# кроме владельца, — и правило это прямо разрешает.
#
# Маркер живёт в /run/user/<uid> (tmpfs): переживает сессии, но не перезагрузку,
# и не может «залипнуть» навсегда. Мёртвый маркер снимается автоматически:
# сессии умирают внезапно, и требовать от них уборки за собой — надеяться на
# память, чего этот набор правил старается не делать.
#
# Команды:
#   orchestrator.sh who      кто оркестратор (код 0 — есть живой, 1 — нет)
#   orchestrator.sh claim [заметка]   объявить себя оркестратором
#   orchestrator.sh release  сложить полномочия (свои или мёртвого)
#   orchestrator.sh status   человекочитаемо, для доклада владельцу
#   orchestrator.sh sessions живые сессии: pid, tty, возраст, простой
#   orchestrator.sh reap [ч] погасить молчащие дольше N часов (по умолчанию 6)
set -uo pipefail

MARK="/run/user/$(id -u)/cc-orchestrator"

# PID своей сессии: ближайший предок с именем claude. Скрипт — потомок хука,
# собственный $$ тут бесполезен.
session_pid() {
  local p=$PPID
  for _ in $(seq 1 12); do
    [[ -z "$p" || "$p" == "1" ]] && break
    local name; name=$(ps -o comm= -p "$p" 2>/dev/null | tr -d ' ')
    [[ "$name" == *claude* ]] && { echo "$p"; return 0; }
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
  echo ""
}

read_mark() {   # печатает "pid|проект|заметка|время", если маркер жив
  [[ -f "$MARK" ]] || return 1
  local pid proj note when
  IFS='|' read -r pid proj note when < "$MARK"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || { rm -f "$MARK"; return 1; }
  printf '%s|%s|%s|%s' "$pid" "$proj" "$note" "$when"
}

case "${1:-status}" in
  who)
    if m=$(read_mark); then
      IFS='|' read -r pid proj note when <<<"$m"
      echo "оркестратор: pid $pid, проект ${proj:-—}, с $when ${note:+($note)}"
      exit 0
    fi
    echo "оркестратора нет"
    exit 1
    ;;

  claim)
    me=$(session_pid)
    [[ -z "$me" ]] && { echo "не смог определить pid своей сессии — маркер не ставлю" >&2; exit 2; }
    if m=$(read_mark); then
      IFS='|' read -r pid proj note when <<<"$m"
      if [[ "$pid" == "$me" ]]; then echo "ты уже оркестратор (с $when)"; exit 0; fi
      echo "оркестратор уже есть: pid $pid, проект ${proj:-—}, с $when." >&2
      echo "Договорись с ним или дождись, пока он сложит полномочия." >&2
      exit 1
    fi
    printf '%s|%s|%s|%s\n' "$me" "$(basename "$PWD")" "${2:-}" "$(date '+%H:%M %d.%m')" > "$MARK"
    echo "ты оркестратор (pid $me). Сложить: orchestrator.sh release"
    ;;

  release)
    me=$(session_pid)
    if m=$(read_mark); then
      IFS='|' read -r pid proj note when <<<"$m"
      if [[ "$pid" != "$me" ]]; then
        echo "маркер не твой (принадлежит живой сессии pid $pid) — не снимаю" >&2
        exit 1
      fi
    fi
    rm -f "$MARK"
    echo "полномочия сложены"
    ;;


  sessions|reap)
    # Живые сессии и их последняя активность. `reap` гасит те, что молчат
    # дольше N часов (по умолчанию 6): `/exit` не всегда снимает процесс —
    # окно закрывают, а оболочка остаётся висеть сутками. Проверено
    # 2026-09-12: из семи сокетов живых было четыре, а из четырёх процессов
    # два не работали со вчерашнего вечера.
    #
    # Свою сессию не трогаем никогда — она определяется тем же способом,
    # что и в claim.
    hours="${2:-6}"
    me=$(session_pid)
    now=$(date +%s)
    killed=0
    proj="$HOME/.claude/projects"
    for s in "/run/user/$(id -u)/cc-socks"/*.sock; do
      [[ -e "$s" ]] || continue
      pid="$(basename "$s" .sock)"
      if ! kill -0 "$pid" 2>/dev/null; then
        [[ "${1:-}" == "reap" ]] && rm -f "$s" && echo "  сокет-сирота снят: $pid"
        continue
      fi
      tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"
      age="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
      # последняя активность: самый свежий транскрипт проекта этой сессии
      cwd="$(readlink -f /proc/$pid/cwd 2>/dev/null)"
      key="$(printf '%s' "$cwd" | sed 's|/|-|g')"
      last=0
      for f in "$proj/$key"/*.jsonl; do
        [[ -e "$f" ]] || continue
        m=$(stat -c %Y "$f"); (( m > last )) && last=$m
      done
      idle_h=$(( last > 0 ? (now - last) / 3600 : -1 ))
      mark=""
      [[ "$pid" == "$me" ]] && mark=" ← это я"
      printf "  pid %-8s %-9s %-8s простой: %sч%s\n" "$pid" "${tty:-—}" "$age" \
             "$([[ $idle_h -ge 0 ]] && echo $idle_h || echo '?')" "$mark"
      if [[ "${1:-}" == "reap" && "$pid" != "$me" && $idle_h -ge $hours ]]; then
        kill -TERM "$pid" 2>/dev/null; sleep 1
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
        echo "      → погашена (молчала ${idle_h}ч, порог ${hours}ч)"
        killed=$((killed + 1))
      fi
    done
    [[ "${1:-}" == "reap" ]] && echo "  погашено: $killed"
    true
    ;;
  status|*)
    if m=$(read_mark); then
      IFS='|' read -r pid proj note when <<<"$m"
      echo "Оркестратор: pid $pid, проект ${proj:-—}, с $when ${note:+· $note}"
    else
      echo "Оркестратора нет."
    fi
    ;;
esac
