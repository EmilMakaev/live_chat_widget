#!/usr/bin/env bash
# Build a new release from the current git checkout and switch to it.
# Run on the VDS as the app user: sudo -u live_chat_widget bash deploy/deploy.sh
#
# Layout:
#   /opt/live_chat_widget/src              <- git checkout (this repo)
#   /opt/live_chat_widget/releases/<ts>/    <- one build per deploy
#   /opt/live_chat_widget/current           <- symlink to the active release

set -euo pipefail

APP_DIR="/opt/live_chat_widget"
SRC_DIR="$APP_DIR/src"
RELEASE_TS="$(date +%Y%m%d%H%M%S)"
RELEASE_DIR="$APP_DIR/releases/$RELEASE_TS"

cd "$SRC_DIR"

echo "==> Pulling latest code"
git pull --ff-only

export MIX_ENV=prod

echo "==> Installing deps"
mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get --only prod

echo "==> Compiling + building assets"
mix compile
mix assets.deploy

echo "==> Building release"
mix release --overwrite

echo "==> Installing release to $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp -a "_build/prod/rel/live_chat_widget/." "$RELEASE_DIR/"
ln -sfn "$RELEASE_DIR" "$APP_DIR/current"

echo "==> Running database migrations"
"$APP_DIR/current/bin/migrate"

echo "==> Restarting service"
sudo systemctl restart live_chat_widget

echo "==> Pruning old releases (keeping last 5)"
cd "$APP_DIR/releases"
ls -1t | tail -n +6 | xargs -r rm -rf

echo "==> Deployed release $RELEASE_TS"
