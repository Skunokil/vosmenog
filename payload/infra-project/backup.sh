#!/usr/bin/env bash
# Полный ежедневный бэкап: БД + файлы + ротация снапшотов
# Использование: backup.sh   (вызывается из cron)
# Требует: ~/projects/infra/.env (креды restic/S3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/backup.log"
KEEP_LAST=14

log() { echo "$(date -Is) $*" | tee -a "$LOG_FILE"; }

log "=== backup start ==="

# Если дампы/файлы упали — скрипт останавливается (set -e),
# ротация НЕ выполняется: старые снапшоты остаются страховкой.
"$SCRIPT_DIR/backup-db.sh" 2>&1 | tee -a "$LOG_FILE"
# Файлы и /etc бэкапим от root — иначе /etc/shadow, ssh-ключи сервера,
# sudoers не читаются (это нужно для восстановления сервера)
sudo -n "$SCRIPT_DIR/backup-files.sh" 2>&1 | tee -a "$LOG_FILE"

set -a; source "$ENV_FILE"; set +a
log "rotate: keep-last $KEEP_LAST"
# --group-by tags: группируем по тегам (db/files), иначе db-снапшоты с
# разными временными путями не считались бы в один лимит
restic forget --keep-last "$KEEP_LAST" --group-by tags --prune 2>&1 | tee -a "$LOG_FILE"

log "=== backup end ==="
