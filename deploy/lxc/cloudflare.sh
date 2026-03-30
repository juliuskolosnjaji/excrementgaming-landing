#!/bin/bash
# excrementgaming Landing — Cloudflare Tunnel helper
# Runs INSIDE the container.
#
# Usage:
#   cloudflare.sh install <TOKEN>
#   cloudflare.sh remove
#   cloudflare.sh status

set -euo pipefail

ACTION="${1:-status}"
TOKEN="${2:-}"

GREEN='\033[1;92m'
RED='\033[01;31m'
YW='\033[33m'
CL='\033[m'
TAB="  "

info()  { echo -e "${TAB}${YW}⠋${CL} $*"; }
ok()    { echo -e "${TAB}${GREEN}✔️ ${CL} $*"; }
error() { echo -e "${TAB}${RED}✖️ ${CL} $*"; exit 1; }

install_cloudflared() {
  if ! command -v cloudflared &>/dev/null; then
    info "Installing cloudflared..."
    local arch
    arch=$(dpkg --print-architecture)
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb" \
      -o /tmp/cloudflared.deb
    dpkg -i /tmp/cloudflared.deb > /dev/null
    rm /tmp/cloudflared.deb
  else
    info "cloudflared already installed."
  fi
}

case "$ACTION" in
  install)
    [[ -z "$TOKEN" ]] && error "Usage: cloudflare.sh install <TOKEN>"
    install_cloudflared
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
      info "Removing existing tunnel service..."
      cloudflared service uninstall 2>/dev/null || true
      sleep 1
    fi
    info "Installing tunnel with provided token..."
    cloudflared service install "$TOKEN"
    systemctl enable cloudflared
    systemctl start cloudflared
    sleep 3
    if systemctl is-active --quiet cloudflared; then
      ok "Cloudflare Tunnel is running."
      echo ""
      echo "  Configure your public hostname in Cloudflare dashboard:"
      echo "    Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames"
      echo "    Add: excrementgaming.com → http://localhost:80"
    else
      error "Tunnel failed to start. Check: journalctl -u cloudflared -n 30"
    fi
    ;;

  remove)
    if ! command -v cloudflared &>/dev/null; then
      info "cloudflared is not installed."
      exit 0
    fi
    info "Removing Cloudflare Tunnel..."
    systemctl stop cloudflared 2>/dev/null || true
    cloudflared service uninstall 2>/dev/null || true
    apt-get remove -y cloudflared > /dev/null 2>&1 || rm -f /usr/local/bin/cloudflared
    ok "Cloudflare Tunnel removed."
    ;;

  status)
    if ! command -v cloudflared &>/dev/null; then
      echo "cloudflared: not installed"
      exit 0
    fi
    echo "cloudflared: $(cloudflared --version 2>&1 | head -1)"
    systemctl is-active --quiet cloudflared 2>/dev/null \
      && echo -e "service:     ${GREEN}running${CL}" \
      || echo -e "service:     ${RED}stopped${CL}"
    ;;

  *)
    error "Unknown action: $ACTION. Use: install <token> | remove | status"
    ;;
esac
