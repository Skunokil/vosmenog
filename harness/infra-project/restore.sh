#!/usr/bin/env bash
# Восстановление из бэкапа restic (S3)
#
# Использование:
#   restore.sh list                      — список снапшотов
#   restore.sh db [SNAP_ID]              — извлечь дампы БД в restore-out/ (безопасно)
#   restore.sh db-apply [SNAP_ID]        — извлечь и ЗАЛИТЬ дампы в контейнеры БД (ДЕСТРУКТИВНО)
#   restore.sh files [SNAP_ID] --target D — восстановить файлы в папку D (безопасно)
#
# SNAP_ID не указан → latest (последний снапшот соответствующего тега)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
OUT_DIR="$SCRIPT_DIR/restore-out"

# !!! ЗАПОЛНИ СВОИ КОНТЕЙНЕРЫ: имя_контейнера:имя_базы:пользователь (совпадает с backup-db.sh)
CONTAINERS=(
  "example-db:app:app"
)

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

cmd="${1:-list}"
shift || true
SNAP="${1:-latest}"
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

case "$cmd" in
  list)
    restic snapshots
    ;;
  db)
    mkdir -p "$OUT_DIR"
    echo "Восстанавливаю дампы (snap=$SNAP)..."
    restic restore "$SNAP" --tag db --target "$OUT_DIR"
    echo "Дампы извлечены в $OUT_DIR/tmp/restic-db.*/ — залей вручную или через: $0 db-apply $SNAP"
    ;;
  db-apply)
    echo "!!! ВНИМАНИЕ: заливка перезапишет данные в контейнерах БД !!!"
    read -r -p "Продолжить? [yes/N]: " ans
    [[ "$ans" == "yes" ]] || { echo "Отменено"; exit 1; }
    mkdir -p "$OUT_DIR"
    restic restore "$SNAP" --tag db --target "$OUT_DIR"
    for entry in "${CONTAINERS[@]}"; do
      IFS=':' read -r cname dbname user <<< "$entry"
      dump_file="$(find "$OUT_DIR/tmp" -name "${cname}_${dbname}.sql.gz" | head -1)"
      [[ -n "$dump_file" ]] || { echo "дамп не найден для $cname — пропуск"; continue; }
      echo "Заливаю $cname ($dbname) из ${dump_file##*/}..."
      gunzip -c "$dump_file" | docker exec -i "$cname" sh -c "psql -U \"$user\" -d \"$dbname\""
      echo "  $cname: залито"
    done
    ;;
  files)
    [[ -n "$TARGET" ]] || { echo "ERROR: нужен --target DIR" >&2; exit 1; }
    mkdir -p "$TARGET"
    echo "Восстанавливаю файлы (snap=$SNAP) в $TARGET ..."
    restic restore "$SNAP" --tag files --target "$TARGET"
    echo "Файлы в $TARGET — скопируй вручную нужное"
    ;;
  *)
    echo "Неизвестная команда: $cmd" >&2
    echo "Доступно: list | db | db-apply | files --target DIR" >&2
    exit 1
    ;;
esac
