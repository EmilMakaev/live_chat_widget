#!/usr/bin/env bash
# One-time VDS provisioning: OS hardening + runtime deps (Erlang/Elixir, Postgres, Caddy).
# Target: Ubuntu 24.04 LTS. Run as root (fresh box) via: sudo bash setup_server.sh
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
apt-get install -y curl git build-essential ufw fail2ban unattended-upgrades \
  unzip gnupg2 ca-certificates

echo "==> Creating unprivileged app user"
id -u "$APP_USER" &>/dev/null || useradd --system --create-home --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR"/{releases,src}
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

echo "==> PostgreSQL"
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql

echo "==> Erlang + Elixir (Erlang Solutions repo)"
curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc \
  -o /usr/share/keyrings/erlang-solutions.asc
echo "deb [signed-by=/usr/share/keyrings/erlang-solutions.asc] https://packages.erlang-solutions.com/ubuntu noble contrib" \
  > /etc/apt/sources.list.d/erlang-solutions.list
apt-get update
apt-get install -y esl-erlang elixir

echo "==> Caddy (reverse proxy + automatic HTTPS)"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

cat <<'EOF'

==> Done. Next steps (see DEPLOY.md):
  1. Create the Postgres role + database for the app.
  2. Copy deploy/live_chat_widget.service to /etc/systemd/system/ and `systemctl daemon-reload`.
  3. Create /etc/live_chat_widget/live_chat_widget.env (chmod 600, root-owned) with your secrets.
  4. Copy deploy/Caddyfile to /etc/caddy/Caddyfile (with your real domain) and `systemctl reload caddy`.
  5. IMPORTANT: only after confirming SSH key login works, harden sshd:
       - PasswordAuthentication no
       - PermitRootLogin no
     in /etc/ssh/sshd_config, then `systemctl restart ssh`.
  6. Run deploy/deploy.sh to build and start the app.
EOF
