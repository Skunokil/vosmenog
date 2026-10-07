#!/usr/bin/env bash
# ============================================================
#  wt — рабочие ветки (git worktree) по правилам раскладки ЭВМ
#  (EPIC-025, ~/agent-os/method/layout.md).
#
#  Место одно: <репо>/.worktrees/<имя>/, имя каталога = имя ветки.
#  Снять можно только влитую и чистую ветку — иначе отказ.
#
#    wt new  <имя> [база]   создать ветку <имя> от базы (по умолч. — ствол)
#    wt done <имя>          снять влитую ветку: каталог + ветку (git branch -d)
#    wt list                ветки репозитория: где лежат, влиты ли
#
#  Запускать из любого места внутри репозитория (или его worktree).
#  Ствол = ветка, на которой стоит основной каталог репозитория.
# ============================================================
set -euo pipefail

die() { printf '\033[1;31m  ✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$1"; }

# основной каталог репозитория (а не текущего worktree)
COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || die "не внутри git-репозитория"
REPO="$(dirname "$COMMON")"
[ "$(basename "$COMMON")" = ".git" ] || die "необычный репозиторий ($COMMON) — разберись руками"
TRUNK="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
WTDIR="$REPO/.worktrees"

ensure_exclude() {
  local ex="$COMMON/info/exclude"
  mkdir -p "$(dirname "$ex")"
  grep -qxF '/.worktrees/' "$ex" 2>/dev/null || echo '/.worktrees/' >> "$ex"
}

check_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]] \
    || die "имя «$1»: только латиница в нижнем регистре, цифры, . _ - (пример: epic-036)"
}

cmd="${1:-list}"; shift || true
case "$cmd" in
  new)
    name="${1:-}"; [ -n "$name" ] || die "wt new <имя> [база]"
    check_name "$name"
    base="${2:-$TRUNK}"
    [ -e "$WTDIR/$name" ] && die "$WTDIR/$name уже есть"
    ensure_exclude
    mkdir -p "$WTDIR"
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/$name"; then
      git -C "$REPO" worktree add "$WTDIR/$name" "$name"
    else
      git -C "$REPO" worktree add -b "$name" "$WTDIR/$name" "$base"
    fi
    ok "ветка $name → $WTDIR/$name (база $base)"
    ;;
  done)
    name="${1:-}"; [ -n "$name" ] || die "wt done <имя>"
    path="$WTDIR/$name"
    [ -d "$path" ] || die "нет $path (worktree вне .worktrees снимается руками: git worktree remove <путь>)"
    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD)"
    if [ -n "$(git -C "$path" status --porcelain)" ]; then
      git -C "$path" status --short | sed 's/^/      /' >&2
      die "в $name незакоммиченное — не снимаю"
    fi
    git -C "$REPO" merge-base --is-ancestor "$branch" "$TRUNK" \
      || die "ветка $branch не влита в $TRUNK ($(git -C "$REPO" rev-list --count "$TRUNK..$branch") комм.) — не снимаю"
    git -C "$REPO" worktree remove "$path"
    git -C "$REPO" branch -d "$branch" >/dev/null
    ok "снята: $name (ветка $branch влита в $TRUNK, удалена)"
    ;;
  list)
    git -C "$REPO" worktree list --porcelain | awk '
      /^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8); sub("refs/heads/","",b); print p"\t"b}' \
    | tail -n +2 | while IFS=$'\t' read -r p b; do
        if git -C "$REPO" merge-base --is-ancestor "$b" "$TRUNK" 2>/dev/null; then m="влита"; else m="в работе"; fi
        case "$p" in "$WTDIR"/*) w="на месте";; *) w="НЕ НА МЕСТЕ";; esac
        printf '  %-40s %-28s %-9s %s\n' "$p" "$b" "$m" "$w"
      done
    ;;
  *) die "команды: new | done | list" ;;
esac
