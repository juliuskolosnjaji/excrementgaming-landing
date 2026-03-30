#!/usr/bin/env bash
# excrementgaming.com Landing Page — Proxmox VE Install Script
# Author: juliuskolosnjaji
# Source: https://github.com/juliuskolosnjaji/excrementgaming-landing
#
# Run on the Proxmox host:
#   bash <(curl -fsSL https://raw.githubusercontent.com/juliuskolosnjaji/excrementgaming-landing/main/deploy/lxc/install.sh)

set -Eeuo pipefail

# ==============================================================================
# Colors & Formatting
# ==============================================================================

YW=$'\033[33m'
YWB=$'\033[93m'
BL=$'\033[36m'
RD=$'\033[01;31m'
BGN=$'\033[4;92m'
GN=$'\033[1;92m'
DGN=$'\033[32m'
CL=$'\033[m'
BOLD=$'\033[1m'
BFR="\\r\\033[K"
TAB="  "

CM="${TAB}✔️ ${TAB}"
CROSS="${TAB}✖️ ${TAB}"
INFO="${TAB}💡${TAB}"
CREATING="${TAB}🚀${TAB}"
GATEWAY="${TAB}🌐${TAB}"
CONTAINERID="${TAB}🆔${TAB}"
CLOUD="${TAB}☁️ ${TAB}"

# ==============================================================================
# Header
# ==============================================================================

header_info() {
  clear
  cat <<"EOF"
                                         _
  _____  _____ _ __ ___ _ __ ___   ___ _ __ | |_  __ _  __ _ _ __ ___ (_)_ __   __ _
 / _ \ \/ / __| '__/ _ \ '_ ` _ \ / _ \ '_ \| __| / _` |/ _` | '_ ` _ \| | '_ \ / _` |
|  __/>  < (__| | |  __/ | | | | |  __/ | | | |_ | (_| | (_| | | | | | | | | | | (_| |
 \___/_/\_\___|_|  \___|_| |_| |_|\___|_| |_|\__| \__, |\__,_|_| |_| |_|_|_| |_|\__, |
                                                   |___/                           |___/

EOF
  echo -e "${DGN}    Landing Page — LXC Install${CL}   ${YW}github.com/juliuskolosnjaji/excrementgaming-landing${CL}"
  echo -e "    ${BL}────────────────────────────────────────────────────────────────────────────${CL}"
  echo ""
}

# ==============================================================================
# Helpers
# ==============================================================================

msg_info()  { local msg="$1"; echo -ne "${TAB}${YW}⠋${CL} ${msg}..."; }
msg_ok()    { local msg="$1"; echo -e "${BFR}${CM}${GN}${msg}${CL}"; }
msg_error() { local msg="$1"; echo -e "${BFR}${CROSS}${RD}${msg}${CL}"; }

catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

error_handler() {
  local line="$1" cmd="$2"
  msg_error "Error on line ${line}: ${cmd}"
  if [[ -n "${CT_ID:-}" ]] && pct status "$CT_ID" &>/dev/null; then
    echo -e "\n${INFO}${YW}Container CT${CT_ID} may be in an incomplete state.${CL}"
    read -rp "${TAB}Remove CT${CT_ID}? [y/N]: " yn
    [[ "${yn,,}" == "y" ]] && { pct stop "$CT_ID" 2>/dev/null || true; pct destroy "$CT_ID" --purge 2>/dev/null || true; msg_ok "Removed CT${CT_ID}"; }
  fi
  exit 1
}

check_proxmox() {
  command -v pct &>/dev/null || { msg_error "This script must run on a Proxmox VE host."; exit 1; }
  [[ $EUID -ne 0 ]] && { msg_error "Run as root."; exit 1; }
  if ! command -v whiptail &>/dev/null; then
    echo -ne "${TAB}${YW}⠋${CL} Installing whiptail..."
    apt-get install -y whiptail > /dev/null 2>&1
    echo -e "${BFR}${CM}${GN}whiptail installed${CL}"
  fi
}

# ==============================================================================
# Defaults
# ==============================================================================

APP="excrementgaming Landing"
NSAPP="excrementgaming"
REPO="https://github.com/juliuskolosnjaji/excrementgaming-landing.git"
GITHUB_RAW="https://raw.githubusercontent.com/juliuskolosnjaji/excrementgaming-landing/main/deploy/lxc"
WEB_ROOT="/var/www/excrementgaming"
SERVICE_NAME="nginx"

var_ram="256"
var_disk="2"

# ==============================================================================
# Main
# ==============================================================================

header_info
check_proxmox
catch_errors

# ── Detect existing installation ──────────────────────────────────────────────
EXISTING_CT=""
for id in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
  if pct exec "$id" -- test -d "$WEB_ROOT" 2>/dev/null; then
    EXISTING_CT="$id"
    break
  fi
done

# ── Mode selection ────────────────────────────────────────────────────────────
if [[ -n "$EXISTING_CT" ]]; then
  CT_HOSTNAME=$(pct config "$EXISTING_CT" | grep "^hostname:" | awk '{print $2}')
  CT_STATUS=$(pct status "$EXISTING_CT" | awk '{print $2}')

  echo -e "${INFO}${YW}Found existing install in CT${EXISTING_CT} (${CT_HOSTNAME}, ${CT_STATUS})${CL}\n"

  ACTION=$(whiptail --backtitle "excrementgaming Landing" \
    --title "Existing Installation Detected" \
    --menu "\nWhat would you like to do?" 14 60 3 \
    "1" "Update site in CT${EXISTING_CT}" \
    "2" "Manage Cloudflare Tunnel in CT${EXISTING_CT}" \
    "3" "Create a new container" \
    3>&1 1>&2 2>&3) || { echo -e "\n${INFO}${YW}Cancelled.${CL}"; exit 0; }
else
  ACTION="new"
fi

# ==============================================================================
# UPDATE
# ==============================================================================
if [[ "$ACTION" == "1" ]]; then
  header_info
  CT_ID="$EXISTING_CT"
  [[ "$(pct status "$CT_ID" | awk '{print $2}')" != "running" ]] && { msg_info "Starting CT${CT_ID}"; pct start "$CT_ID"; sleep 3; msg_ok "Started CT${CT_ID}"; }

  msg_info "Pulling latest from GitHub"
  pct exec "$CT_ID" -- bash -c "
    cd /opt/excrementgaming-landing
    git fetch --quiet origin main
    BEFORE=\$(git rev-parse HEAD)
    git reset --hard origin/main --quiet
    AFTER=\$(git rev-parse HEAD)
    rsync -a --delete --exclude='.git' /opt/excrementgaming-landing/ $WEB_ROOT/
    nginx -t 2>/dev/null && systemctl reload nginx
    echo \"\$BEFORE \$AFTER\"
  " > /tmp/excg_update_out 2>&1

  RESULT=$(cat /tmp/excg_update_out | tail -1)
  BEFORE=$(echo "$RESULT" | awk '{print $1}' | cut -c1-7)
  AFTER=$(echo "$RESULT" | awk '{print $2}' | cut -c1-7)
  [[ "$BEFORE" == "$AFTER" ]] && msg_ok "Already up to date" || msg_ok "Updated ${BEFORE} → ${AFTER}"

  CT_IP=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
  echo -e "\n${CM}${GN}Update complete!${CL}"
  echo -e "${GATEWAY}${BGN}http://${CT_IP}${CL}\n"
  exit 0
fi

# ==============================================================================
# CLOUDFLARE management
# ==============================================================================
if [[ "$ACTION" == "2" ]]; then
  header_info
  CT_ID="$EXISTING_CT"
  [[ "$(pct status "$CT_ID" | awk '{print $2}')" != "running" ]] && { msg_info "Starting CT${CT_ID}"; pct start "$CT_ID"; sleep 3; msg_ok "Started"; }
  _manage_cloudflare "$CT_ID"
  exit 0
fi

# ==============================================================================
# Cloudflare helper
# ==============================================================================
_manage_cloudflare() {
  local ct="$1"
  CF_RUNNING=$(pct exec "$ct" -- bash -c "command -v cloudflared &>/dev/null && systemctl is-active --quiet cloudflared && echo yes || echo no" 2>/dev/null || echo "no")

  if [[ "$CF_RUNNING" == "yes" ]]; then
    CF_ACTION=$(whiptail --backtitle "excrementgaming Landing" \
      --title "Cloudflare Tunnel" \
      --menu "\nTunnel is currently running." 13 60 3 \
      "1" "Keep existing tunnel" \
      "2" "Replace tunnel token" \
      "3" "Remove tunnel" \
      3>&1 1>&2 2>&3) || return 0
  else
    CF_ACTION=$(whiptail --backtitle "excrementgaming Landing" \
      --title "Cloudflare Tunnel (optional)" \
      --menu "\nExpose the site without opening ports." 13 60 2 \
      "1" "Skip — LAN access only" \
      "2" "Set up Cloudflare Tunnel" \
      3>&1 1>&2 2>&3) || return 0
    [[ "$CF_ACTION" == "1" ]] && { msg_ok "Skipping Cloudflare Tunnel"; return 0; }
    CF_ACTION="2"
  fi

  case "$CF_ACTION" in
    2)
      CF_TOKEN=$(whiptail --backtitle "excrementgaming Landing" \
        --title "Cloudflare Tunnel Token" \
        --inputbox "\nPaste your tunnel token.\n\nGet it at:\n  dash.cloudflare.com → Zero Trust\n  → Networks → Tunnels → Create\n" \
        16 70 3>&1 1>&2 2>&3) || return 0
      [[ -z "$CF_TOKEN" ]] && { msg_error "No token entered — skipping"; return 0; }
      msg_info "Installing Cloudflare Tunnel"
      pct exec "$ct" -- bash -c "curl -fsSL $GITHUB_RAW/cloudflare.sh -o /tmp/cloudflare.sh && bash /tmp/cloudflare.sh install '$CF_TOKEN'"
      msg_ok "Cloudflare Tunnel installed"
      ;;
    3)
      msg_info "Removing Cloudflare Tunnel"
      pct exec "$ct" -- bash -c "curl -fsSL $GITHUB_RAW/cloudflare.sh -o /tmp/cloudflare.sh && bash /tmp/cloudflare.sh remove"
      msg_ok "Removed"
      ;;
    *) msg_ok "Keeping existing tunnel" ;;
  esac
}

# ==============================================================================
# NEW container
# ==============================================================================
header_info

if (whiptail --backtitle "excrementgaming Landing" \
  --title "Settings" \
  --yesno "Use default settings?\n\n  RAM:   ${var_ram} MB\n  Disk:  ${var_disk} GB\n  OS:    Debian 12\n  Type:  Unprivileged" \
  13 50); then
  SETTINGS="default"
else
  SETTINGS="advanced"
fi

next_id() { local id=100; while pct status "$id" &>/dev/null 2>&1; do id=$((id+1)); done; echo "$id"; }
DEFAULT_CTID=$(next_id)

if [[ "$SETTINGS" == "advanced" ]]; then
  CT_ID=$(whiptail --backtitle "excrementgaming Landing" --title "Container ID" \
    --inputbox "\nEnter container ID:" 9 50 "$DEFAULT_CTID" 3>&1 1>&2 2>&3) || exit 0
  CT_ID="${CT_ID:-$DEFAULT_CTID}"
  pct status "$CT_ID" &>/dev/null && { msg_error "CT${CT_ID} already exists."; exit 1; }

  CT_HOSTNAME=$(whiptail --backtitle "excrementgaming Landing" --title "Hostname" \
    --inputbox "\nEnter hostname:" 9 50 "$NSAPP" 3>&1 1>&2 2>&3) || exit 0
  CT_HOSTNAME="${CT_HOSTNAME:-$NSAPP}"

  CT_RAM=$(whiptail --backtitle "excrementgaming Landing" --title "RAM" \
    --inputbox "\nRAM in MB:" 9 40 "$var_ram" 3>&1 1>&2 2>&3) || exit 0
  CT_RAM="${CT_RAM:-$var_ram}"

  CT_DISK=$(whiptail --backtitle "excrementgaming Landing" --title "Disk" \
    --inputbox "\nDisk size in GB:" 9 40 "$var_disk" 3>&1 1>&2 2>&3) || exit 0
  CT_DISK="${CT_DISK:-$var_disk}"

  STORAGE_LIST=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1 " " $1}')
  CT_STORAGE=$(whiptail --backtitle "excrementgaming Landing" --title "Storage" \
    --menu "\nSelect storage:" 14 50 4 $STORAGE_LIST 3>&1 1>&2 2>&3) || exit 0

  BRIDGE_LIST=$(ip link show | awk '/^[0-9]+: vmbr/{gsub(":",""); print $2 " " $2}')
  CT_BRIDGE=$(whiptail --backtitle "excrementgaming Landing" --title "Bridge" \
    --menu "\nSelect bridge:" 13 50 4 $BRIDGE_LIST 3>&1 1>&2 2>&3) || exit 0
else
  CT_ID="$DEFAULT_CTID"
  CT_HOSTNAME="$NSAPP"
  CT_RAM="$var_ram"
  CT_DISK="$var_disk"
  CT_STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR==2 {print $1}')
  CT_STORAGE="${CT_STORAGE:-local-lvm}"
  CT_BRIDGE="vmbr0"
fi

CT_PW=$(whiptail --backtitle "excrementgaming Landing" --title "Root Password" \
  --passwordbox "\nSet a root password (leave blank to disable):" 10 50 3>&1 1>&2 2>&3) || exit 0

whiptail --backtitle "excrementgaming Landing" --title "Confirm" \
  --yesno "\n  CT ID:    ${CT_ID}\n  Hostname: ${CT_HOSTNAME}\n  RAM:      ${CT_RAM} MB\n  Disk:     ${CT_DISK} GB\n  Storage:  ${CT_STORAGE}\n  Bridge:   ${CT_BRIDGE}\n\nProceed?" \
  16 50 || { echo -e "\n${INFO}${YW}Cancelled.${CL}"; exit 0; }

# ── Build ─────────────────────────────────────────────────────────────────────
header_info
echo -e "${CREATING}${GN}Creating CT${CT_ID} (${CT_HOSTNAME})${CL}\n"

msg_info "Checking Debian 12 template"
TEMPLATE=$(pveam list local 2>/dev/null | grep -i "debian-12" | head -1 | awk '{print $1}')
if [[ -z "$TEMPLATE" ]]; then
  pveam update > /dev/null 2>&1
  TEMPLATE_NAME=$(pveam available --section system 2>/dev/null | grep -i "debian-12" | head -1 | awk '{print $2}')
  [[ -z "$TEMPLATE_NAME" ]] && { msg_error "Debian 12 template not found."; exit 1; }
  pveam download local "$TEMPLATE_NAME" > /dev/null 2>&1
  TEMPLATE="local:vztmpl/$TEMPLATE_NAME"
fi
msg_ok "Template ready"

msg_info "Creating container"
PCT_ARGS=(
  "$CT_ID" "$TEMPLATE"
  --hostname "$CT_HOSTNAME"
  --memory "$CT_RAM"
  --swap 256
  --rootfs "${CT_STORAGE}:${CT_DISK}"
  --cores 1
  --net0 "name=eth0,bridge=${CT_BRIDGE},ip=dhcp"
  --unprivileged 1
  --features "nesting=1"
  --ostype "debian"
  --start 1
)
[[ -n "$CT_PW" ]] && PCT_ARGS+=(--password "$CT_PW")
pct create "${PCT_ARGS[@]}" > /dev/null 2>&1
msg_ok "Container CT${CT_ID} created"

msg_info "Waiting for network"
for i in {1..30}; do
  pct exec "$CT_ID" -- curl -fsSL --max-time 3 https://github.com &>/dev/null && break || sleep 2
done
msg_ok "Network ready"

msg_info "Installing nginx and git"
pct exec "$CT_ID" -- bash -c "
  apt-get update -qq
  apt-get install -y --no-install-recommends nginx git curl > /dev/null
  systemctl enable nginx > /dev/null
" > /dev/null 2>&1
msg_ok "nginx installed"

msg_info "Deploying site from GitHub"
pct exec "$CT_ID" -- bash -c "
  git clone --depth 1 https://github.com/juliuskolosnjaji/excrementgaming-landing.git /opt/excrementgaming-landing > /dev/null 2>&1
  mkdir -p $WEB_ROOT
  rsync -a --exclude='.git' /opt/excrementgaming-landing/ $WEB_ROOT/
  chown -R www-data:www-data $WEB_ROOT
" > /dev/null 2>&1
msg_ok "Site deployed"

msg_info "Configuring nginx"
pct exec "$CT_ID" -- bash -c "
  cp /opt/excrementgaming-landing/nginx.conf /etc/nginx/sites-available/excrementgaming
  ln -sf /etc/nginx/sites-available/excrementgaming /etc/nginx/sites-enabled/excrementgaming
  rm -f /etc/nginx/sites-enabled/default
  nginx -t > /dev/null 2>&1
  systemctl reload nginx
" > /dev/null 2>&1
msg_ok "nginx configured"

msg_info "Installing update script"
pct exec "$CT_ID" -- bash -c "
  cp /opt/excrementgaming-landing/deploy/lxc/update.sh /usr/local/bin/excg-update
  chmod +x /usr/local/bin/excg-update
" > /dev/null 2>&1
msg_ok "Update script installed"

_manage_cloudflare "$CT_ID"

# ── Done ──────────────────────────────────────────────────────────────────────
CT_IP=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")

echo ""
echo -e "${CM}${GN}${BOLD}${APP} setup complete!${CL}"
echo ""
echo -e "${CONTAINERID}${BL}Container:${CL}  CT${CT_ID} (${CT_HOSTNAME})"
echo -e "${GATEWAY}${BL}LAN access:${CL} ${BGN}http://${CT_IP}${CL}"
echo ""
echo -e "${INFO}${YW}Useful commands:${CL}"
echo -e "${TAB}Update site:  ${BOLD}pct exec ${CT_ID} -- excg-update${CL}"
echo -e "${TAB}View logs:    ${BOLD}pct exec ${CT_ID} -- tail -f /var/log/nginx/excrementgaming.access.log${CL}"
echo -e "${TAB}Re-run:       ${BOLD}bash <(curl -fsSL ${GITHUB_RAW}/install.sh)${CL}"
echo ""
