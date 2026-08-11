#!/usr/bin/env bash
# Nightly Postgres backup: pg_dump (custom format, compressed) + local rotation.
# Postgres runs in the `db` container (docker-compose.yml) — no exposed port,
# no host-level Postgres client needed, we just exec into the container.
# Install: crontab -e (as root) →
#   0 3 * * * /opt/live_chat_widget/src/deploy/backup_db.sh >> /var/log/live_chat_widget-backup.log 2>&1

set -euo pipefail

# Silences "POSTGRES_PASSWORD variable is not set" — docker-compose.yml
# reads it for the db service's own env, cron doesn't have it otherwise.
set -a
source /etc/live_chat_widget/live_chat_widget.env
set +a

DB_NAME="live_chat_widget_prod"
DB_USER="live_chat_widget"
BACKUP_DIR="/var/backups/live_chat_widget"
KEEP_DAYS=14
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.dump"

mkdir -p "$BACKUP_DIR"

docker compose -f /opt/live_chat_widget/src/docker-compose.yml exec -T db \
  pg_dump -Fc -U "$DB_USER" "$DB_NAME" > "$FILE"
chown live_chat_widget:live_chat_widget "$FILE"
chmod 640 "$FILE"

echo "$(date -Iseconds) backed up to $FILE ($(du -h "$FILE" | cut -f1))"

find "$BACKUP_DIR" -name "${DB_NAME}_*.dump" -mtime "+${KEEP_DAYS}" -print -delete
