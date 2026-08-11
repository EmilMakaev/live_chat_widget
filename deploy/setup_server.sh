#!/usr/bin/env bash
# One-time VDS provisioning: OS hardening + Docker + Caddy.
# Target: Ubuntu 24.04 LTS. Run as root (fresh box) via: sudo bash setup_server.sh
#
# Everything the app needs to run (Erlang/Elixir/Postgres) now lives inside
# containers — the app image is built in CI, Postgres is the official
# `postgres` image. This box only needs Docker itself and a reverse proxy.
#
# Read DEPLOY.md before running this — in particular, set up your SSH key
# and confirm key-based login works in a SEPARATE terminal before this
# script disables SSH password auth, or you can lock yourself out.

set -euo pipefail

APP_USER="live_chat_widget"
APP_DIR="/opt/live_chat_widget"

echo "==> Updating base system"
apt-get update && apt-get -y upgrade

echo "==> Installing base tools"
apt-get install -y curl git ufw fail2ban unattended-upgrades \
  unzip gnupg2 ca-certificates

echo "==> Creating app user (needs a real shell — forced-command SSH deploy key uses it)"
id -u "$APP_USER" &>/dev/null || useradd --create-home --shell /bin/bash "$APP_USER"
mkdir -p "$APP_DIR"/src
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

echo "==> Firewall: allow SSH, HTTP, HTTPS only"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> fail2ban: default sshd jail"
systemctl enable --now fail2ban

echo "==> Unattended security upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Docker"
curl -fsSL https://get.docker.com | sh

echo "==> Caddy (reverse proxy + automatic HTTPS)"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

cat <<'EOF'

==> Done. Next steps (see DEPLOY.md):
  1. Create /etc/live_chat_widget/live_chat_widget.env (chmod 640, root:live_chat_widget group) with your secrets.
  2. Copy deploy/Caddyfile to /etc/caddy/Caddyfile (with your real domain) and `systemctl reload caddy`.
  3. Allow the app user to run deploy.sh as root (see DEPLOY.md section 5).
  4. IMPORTANT: only after confirming SSH key login works, harden sshd:
       - PasswordAuthentication no
       - PermitRootLogin no
     in /etc/ssh/sshd_config, then `systemctl restart ssh`.
  5. Run deploy/deploy.sh to pull and start the app + database containers.
EOF
