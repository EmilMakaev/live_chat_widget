#!/usr/bin/env bash
# Nightly Postgres backup: pg_dump (custom format, compressed) + local rotation.
# Runs as root via cron (uses `sudo -u postgres` — local peer auth, no password
# needed). Install: crontab -e (as root) →
#   0 3 * * * /opt/live_chat_widget/src/deploy/backup_db.sh >> /var/log/live_chat_widget-backup.log 2>&1

set -euo pipefail

DB_NAME="live_chat_widget_prod"
BACKUP_DIR="/var/backups/live_chat_widget"
KEEP_DAYS=14
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"

mkdir -p "$BACKUP_DIR"

sudo -u postgres pg_dump -Fc "$DB_NAME" > "$FILE"
chown live_chat_widget:live_chat_widget "$FILE"
chmod 640 "$FILE"

echo "$(date -Iseconds) backed up to $FILE ($(du -h "$FILE" | cut -f1))"

find "$BACKUP_DIR" -name "${DB_NAME}_*.dump" -mtime "+${KEEP_DAYS}" -print -delete
