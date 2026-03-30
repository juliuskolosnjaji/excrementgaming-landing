#!/bin/bash
# excrementgaming Landing — update script
# Installed to /usr/local/bin/excg-update during setup.
# Run as root inside the container to pull the latest site from GitHub.

set -euo pipefail

REPO_DIR="/opt/excrementgaming-landing"
WEB_ROOT="/var/www/excrementgaming"

GREEN='\033[1;92m'
RED='\033[01;31m'
YW='\033[33m'
CL='\033[m'
TAB="  "

info()  { echo -e "${TAB}${YW}⠋${CL} $*"; }
ok()    { echo -e "${TAB}${GREEN}✔️ ${CL} $*"; }
error() { echo -e "${TAB}${RED}✖️ ${CL} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root."
[[ -d "$REPO_DIR/.git" ]] || error "Repo not found at $REPO_DIR. Run install.sh first."

info "Fetching latest from GitHub..."
BEFORE=$(git -C "$REPO_DIR" rev-parse HEAD)
git -C "$REPO_DIR" fetch --quiet origin main
git -C "$REPO_DIR" reset --hard origin/main --quiet
AFTER=$(git -C "$REPO_DIR" rev-parse HEAD)

if [[ "$BEFORE" == "$AFTER" ]]; then
  ok "Already up to date."
  exit 0
fi

ok "Updated: ${BEFORE:0:7} → ${AFTER:0:7}"
git -C "$REPO_DIR" log --oneline "${BEFORE}..${AFTER}"

info "Syncing files to web root..."
rsync -a --delete --exclude='.git' "$REPO_DIR/" "$WEB_ROOT/"
chown -R www-data:www-data "$WEB_ROOT"

info "Reloading nginx..."
nginx -t 2>/dev/null && systemctl reload nginx

# Refresh this script itself
cp "$REPO_DIR/deploy/lxc/update.sh" /usr/local/bin/excg-update
chmod +x /usr/local/bin/excg-update

ok "Update complete."
