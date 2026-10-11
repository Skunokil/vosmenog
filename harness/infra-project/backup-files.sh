#!/usr/bin/env bash
# Файловый бэкап рабочих путей → restic (тег files)
# Использование: backup-files.sh  (запускать через sudo -n — /etc от root)
# Требует: ~/projects/infra/.env (креды restic/S3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

[[ -f "$ENV_FILE" ]] || { echo "ERROR: $ENV_FILE not found" >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

# Что бэкапим: код/документация, ssh-ключи, конфиги агента, дистрибутив, системные конфиги
BACKUP_PATHS=(
  /home/skunokil/projects
  /home/skunokil/.ssh
  /home/skunokil/.claude
  /home/skunokil/.config/opencode
  /home/skunokil/agent-os
  /etc
)

restic backup --tag files \
  --exclude '**/node_modules' \
  --exclude '**/*.log' \
  "${BACKUP_PATHS[@]}"

echo "files backup done"
