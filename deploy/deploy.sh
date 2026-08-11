#!/usr/bin/env bash
# Pull the freshly-built image from GHCR and switch to it. Runs as root
# (via the deploy user's forced `sudo` command — see DEPLOY.md "CI/CD"),
# because managing Docker containers needs root/docker-group access anyway;
# scoping *which script* can run as root is the actual security boundary
# here, not which user invokes it.
#
# Image build happens in GitHub Actions (real amd64 hardware, plenty of
# RAM) — this script never compiles anything, just pulls + restarts.

set -euo pipefail

SRC_DIR="/opt/live_chat_widget/src"
cd "$SRC_DIR"

# docker-compose.yml's ${POSTGRES_PASSWORD} is substituted from *this
# shell's* environment, not from the app container's env_file: — same
# secrets file, two different consumption paths.
set -a
source /etc/live_chat_widget/live_chat_widget.env
set +a

echo "==> Pulling latest docker-compose.yml / Caddyfile / migration files"
git pull --ff-only

echo "==> Pulling image"
docker compose pull

echo "==> Running database migrations"
docker compose run --rm app bin/migrate

echo "==> Restarting"
docker compose up -d

echo "==> Pruning unused images (keeps the last few, drops the rest)"
docker image prune -f

echo "==> Deployed $(docker compose images app --format '{{.Tag}}' 2>/dev/null || echo unknown)"
