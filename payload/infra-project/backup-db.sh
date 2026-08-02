#!/usr/bin/env bash
# Бэкап PostgreSQL контейнеров через pg_dump → restic (тег db)
# Использование: backup-db.sh
# Требует: ~/projects/infra/.env (креды restic/S3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# !!! ЗАПОЛНИ СВОИ КОНТЕЙНЕРЫ: имя_контейнера:имя_базы:пользователь
# Например: "my-postgres:app:app"
CONTAINERS=(
  "example-db:app:app"
)

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

# Временная папка для дампов (mktemp + trap на rm — безопасно)
TMPDIR="$(mktemp -d /tmp/restic-db.XXXXXX)"
trap 'rm -rf -- "$TMPDIR"' EXIT

DUMPS=()
for entry in "${CONTAINERS[@]}"; do
  IFS=':' read -r cname dbname user <<< "$entry"
  dump="$TMPDIR/${cname}_${dbname}.sql.gz"
  echo "dumping $cname ($dbname)..."
  if docker exec "$cname" sh -c "pg_dump -U \"$user\" -d \"$dbname\"" | gzip > "$dump"; then
    DUMPS+=("$dump")
    echo "  ok: ${dump##*/} ($(du -h "$dump" | cut -f1))"
  else
    echo "  FAILED: $cname" >&2
  fi
done

[[ ${#DUMPS[@]} -gt 0 ]] || { echo "ERROR: no dumps produced" >&2; exit 1; }

restic backup --tag db "${DUMPS[@]}"
echo "db backup done"
