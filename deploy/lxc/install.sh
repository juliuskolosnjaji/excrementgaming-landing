#!/usr/bin/env bash
# excrementgaming.com Landing Page — Proxmox VE Install Script
# Author: juliuskolosnjaji
# Source: https://github.com/juliuskolosnjaji/excrementgaming-landing
#
# Run on the Proxmox host:
#   bash <(curl -fsSL https://raw.githubusercontent.com/juliuskolosnjaji/excrementgaming-landing/main/deploy/lxc/install.sh)

set -euo pipefail

# ==============================================================================
# Colors & Formatting
# ==============================================================================

YW=$'\033[33m'
BL=$'\033[36m'
RD=$'\033[01;31m'
BGN=$'\033[4;92m'
GN=$'\033[1;92m'
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
# Helpers
# ==============================================================================

msg_info()  { echo -ne "${TAB}${YW}⠋${CL} ${1}..."; }
msg_ok()    { echo -e "${BFR}${CM}${GN}${1}${CL}"; }
msg_error() { echo -e "${BFR}${CROSS}${RD}${1}${CL}"; }

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
  echo -e "${GN}    Landing Page — LXC Install${CL}   ${YW}github.com/juliuskolosnjaji/excrementgaming-landing${CL}"
  echo -e "    ${BL}────────────────────────────────────────────────────────────────────────────${CL}"
  echo ""
}

next_id() {
  local id=100
  while id_in_use "$id"; do id=$((id + 1)); done
  echo "$id"
}

id_in_use() {
  local id="$1"
  pct status "$id" &>/dev/null 2>&1 || qm status "$id" &>/dev/null 2>&1
}

first_storage_for_content() {
  local content="$1"
  pvesm status -content "$content" 2>/dev/null | awk 'NR>1 {print $1; exit}'
}

first_bridge() {
  ip link show 2>/dev/null | awk '/^[0-9]+: vmbr/{gsub(":",""); print $2; exit}'
}

# ==============================================================================
# Cloudflare helper — defined before use
# ==============================================================================

_manage_cloudflare() {
  local ct="$1"
  local CF_RUNNING
  CF_RUNNING=$(pct exec "$ct" -- bash -c "command -v cloudflared &>/dev/null && systemctl is-active --quiet cloudflared && echo yes || echo no" 2>/dev/null || echo "no")

  local CF_ACTION
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
      local CF_TOKEN
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
# Defaults
# ==============================================================================

APP="excrementgaming Landing"
NSAPP="excrementgaming"
GITHUB_RAW="https://raw.githubusercontent.com/juliuskolosnjaji/excrementgaming-landing/main/deploy/lxc"
WEB_ROOT="/var/www/excrementgaming"

var_ram="256"
var_disk="2"

# ==============================================================================
# Preflight
# ==============================================================================

header_info

command -v pct &>/dev/null  || { msg_error "This script must run on a Proxmox VE host."; exit 1; }
[[ $EUID -ne 0 ]]           && { msg_error "Run as root."; exit 1; }

if ! command -v whiptail &>/dev/null; then
  msg_info "Installing whiptail"
  apt-get install -y whiptail > /dev/null 2>&1
  msg_ok "whiptail installed"
fi

# ==============================================================================
# Detect existing installation (safe — no set -e yet)
# ==============================================================================

EXISTING_CT=""
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  if pct exec "$id" -- test -d "$WEB_ROOT" 2>/dev/null; then
    EXISTING_CT="$id"
    break
  fi
done < <(pct list 2>/dev/null | awk 'NR>1 {print $1}')

# ==============================================================================
# Mode selection
# ==============================================================================

ACTION="new"

if [[ -n "$EXISTING_CT" ]]; then
  CT_HOSTNAME=$(pct config "$EXISTING_CT" | awk '/^hostname:/{print $2}')
  CT_STATUS=$(pct status "$EXISTING_CT" | awk '{print $2}')
  echo -e "${INFO}${YW}Found existing install in CT${EXISTING_CT} (${CT_HOSTNAME}, ${CT_STATUS})${CL}\n"

  ACTION=$(whiptail --backtitle "excrementgaming Landing" \
    --title "Existing Installation Detected" \
    --menu "\nWhat would you like to do?" 14 60 3 \
    "1" "Update site in CT${EXISTING_CT}" \
    "2" "Manage Cloudflare Tunnel in CT${EXISTING_CT}" \
    "3" "Create a new container" \
    3>&1 1>&2 2>&3) || { echo -e "\n${INFO}${YW}Cancelled.${CL}"; exit 0; }
fi

# From here, enable strict error handling
set -Eeuo pipefail
trap 'echo -e "\n${CROSS}${RD}Error on line ${LINENO}. Aborted.${CL}"' ERR

# ==============================================================================
# UPDATE existing container
# ==============================================================================

if [[ "$ACTION" == "1" ]]; then
  header_info
  CT_ID="$EXISTING_CT"
  if [[ "$(pct status "$CT_ID" | awk '{print $2}')" != "running" ]]; then
    msg_info "Starting CT${CT_ID}"; pct start "$CT_ID"; sleep 3; msg_ok "Started CT${CT_ID}"
  fi

  msg_info "Pulling latest from GitHub"
  pct exec "$CT_ID" -- bash -c "
    cd /opt/excrementgaming-landing
    git fetch --quiet origin main
    BEFORE=\$(git rev-parse HEAD)
    git reset --hard origin/main --quiet
    AFTER=\$(git rev-parse HEAD)
    rsync -a --delete --exclude='.git' /opt/excrementgaming-landing/ $WEB_ROOT/
    nginx -t 2>/dev/null && systemctl reload nginx
    echo \"\${BEFORE:0:7} \${AFTER:0:7}\"
  " > /tmp/excg_update_out 2>&1 || true

  read -r BEFORE AFTER < /tmp/excg_update_out || true
  [[ "$BEFORE" == "$AFTER" ]] && msg_ok "Already up to date" || msg_ok "Updated ${BEFORE} → ${AFTER}"

  CT_IP=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
  echo -e "\n${CM}${GN}Update complete!${CL}"
  echo -e "${GATEWAY}${BGN}http://${CT_IP}${CL}\n"
  exit 0
fi

# ==============================================================================
# CLOUDFLARE management only
# ==============================================================================

if [[ "$ACTION" == "2" ]]; then
  header_info
  CT_ID="$EXISTING_CT"
  if [[ "$(pct status "$CT_ID" | awk '{print $2}')" != "running" ]]; then
    msg_info "Starting CT${CT_ID}"; pct start "$CT_ID"; sleep 3; msg_ok "Started"
  fi
  _manage_cloudflare "$CT_ID"
  exit 0
fi

# ==============================================================================
# NEW container
# ==============================================================================

header_info

if whiptail --backtitle "excrementgaming Landing" \
  --title "Settings" \
  --yesno "Use default settings?\n\n  RAM:   ${var_ram} MB\n  Disk:  ${var_disk} GB\n  OS:    Debian 12\n  Type:  Unprivileged" \
  13 50 3>&1 1>&2 2>&3; then
  SETTINGS="default"
else
  SETTINGS="advanced"
fi

DEFAULT_CTID=$(next_id)

if [[ "$SETTINGS" == "advanced" ]]; then
  CT_ID=$(whiptail --backtitle "excrementgaming Landing" --title "Container ID" \
    --inputbox "\nEnter container ID:" 9 50 "$DEFAULT_CTID" 3>&1 1>&2 2>&3) || exit 0
  CT_ID="${CT_ID:-$DEFAULT_CTID}"
  id_in_use "$CT_ID" && { msg_error "ID ${CT_ID} is already in use by an existing VM or container."; exit 1; }

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
    --menu "\nSelect storage:" 14 50 6 $STORAGE_LIST 3>&1 1>&2 2>&3) || exit 0

  BRIDGE_LIST=$(ip link show 2>/dev/null | awk '/^[0-9]+: vmbr/{gsub(":",""); print $2 " " $2}')
  CT_BRIDGE=$(whiptail --backtitle "excrementgaming Landing" --title "Bridge" \
    --menu "\nSelect bridge:" 13 50 4 $BRIDGE_LIST 3>&1 1>&2 2>&3) || exit 0
else
  CT_ID="$DEFAULT_CTID"
  CT_HOSTNAME="$NSAPP"
  CT_RAM="$var_ram"
  CT_DISK="$var_disk"
  CT_STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR==2 {print $1}')
  CT_STORAGE="${CT_STORAGE:-local-lvm}"
  CT_BRIDGE=$(first_bridge)
  CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
fi

CT_PW=$(whiptail --backtitle "excrementgaming Landing" --title "Root Password" \
  --passwordbox "\nSet a root password (leave blank to disable):" 10 50 3>&1 1>&2 2>&3) || exit 0

whiptail --backtitle "excrementgaming Landing" --title "Confirm" \
  --yesno "\n  CT ID:    ${CT_ID}\n  Hostname: ${CT_HOSTNAME}\n  RAM:      ${CT_RAM} MB\n  Disk:     ${CT_DISK} GB\n  Storage:  ${CT_STORAGE}\n  Bridge:   ${CT_BRIDGE}\n\nProceed?" \
  16 50 3>&1 1>&2 2>&3 || { echo -e "\n${INFO}${YW}Cancelled.${CL}"; exit 0; }

# ── Build ─────────────────────────────────────────────────────────────────────
header_info
echo -e "${CREATING}${GN}Creating CT${CT_ID} (${CT_HOSTNAME})${CL}\n"

msg_info "Checking Debian 12 template"
TEMPLATE_STORAGE=$(first_storage_for_content vztmpl)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE=$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -i "debian-12" | head -1 | awk '{print $1}')
if [[ -z "$TEMPLATE" ]]; then
  pveam update > /dev/null 2>&1
  TEMPLATE_NAME=$(pveam available --section system 2>/dev/null | grep -i "debian-12" | head -1 | awk '{print $2}')
  [[ -z "$TEMPLATE_NAME" ]] && { msg_error "Debian 12 template not found."; exit 1; }
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME" > /dev/null 2>&1
  TEMPLATE="${TEMPLATE_STORAGE}:vztmpl/$TEMPLATE_NAME"
fi
msg_ok "Template ready"

msg_info "Creating container"
[[ -n "$CT_STORAGE" ]] || { msg_error "No Proxmox storage with rootdir content available."; exit 1; }
[[ -n "$CT_BRIDGE" ]] || { msg_error "No Proxmox bridge found. Create a vmbr bridge first."; exit 1; }
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
PCT_CREATE_ERR=$(mktemp)
if ! pct create "${PCT_ARGS[@]}" > /dev/null 2>"$PCT_CREATE_ERR"; then
  msg_error "Container creation failed"
  sed 's/^/      /' "$PCT_CREATE_ERR" >&2
  rm -f "$PCT_CREATE_ERR"
  exit 1
fi
rm -f "$PCT_CREATE_ERR"
msg_ok "Container CT${CT_ID} created"

msg_info "Waiting for network"
for i in {1..30}; do
  pct exec "$CT_ID" -- curl -fsSL --max-time 3 https://github.com &>/dev/null && break || sleep 2
done
msg_ok "Network ready"

msg_info "Installing nginx and git"
pct exec "$CT_ID" -- bash -c "
  apt-get update -qq
  apt-get install -y --no-install-recommends nginx git curl rsync > /dev/null
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
