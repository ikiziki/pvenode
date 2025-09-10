#!/usr/bin/env bash
# create-lxc-interactive.sh
# Interactive LXC creator for Proxmox (styled + progress)

set -euo pipefail
NODE="$(hostname -s)"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ---- Helper functions ----
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

choose() {
  local prompt="$1"; shift
  local options=("$@")
  while :; do
    echo
    echo -e "${CYAN}$prompt${RESET}"
    for i in "${!options[@]}"; do
      printf "  %2d) %s\n" $((i+1)) "${options[$i]}"
    done
    read -rp "Choose [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return 0
    fi
    warn "Invalid choice."
  done
}

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "      \b\b\b\b\b\b"
}

get_next_vmid() {
  local nextid
  nextid="$(pvesh get /cluster/nextid 2>/dev/null || true)"
  if [[ -n "$nextid" ]]; then echo "$nextid"; return; fi
  for id in $(seq 100 9999); do
    if ! pct status "$id" >/dev/null 2>&1 && ! qm status "$id" >/dev/null 2>&1; then
      echo "$id"; return
    fi
  done
  error "Couldn't find free VMID"
  exit 1
}

# ---- Step 1: VMID ----
info "Step 1: Determining next available VMID..."
VMID="$(get_next_vmid)"
echo -e "${YELLOW}Suggested VMID: $VMID${RESET}"
read -rp "Use suggested VMID? [Y/n] " use_suggest
if [[ "$use_suggest" =~ ^[Nn] ]]; then
  read -rp "Enter VMID to use: " VMID
fi

# ---- Step 2: Resources ----
info "Step 2: Define container resources..."
read -rp "Hostname: " HOSTNAME
read -rp "Cores (e.g. 2): " CORES
read -rp "Memory in MB (e.g. 2048): " MEMORY
read -rp "Disk size in GB (e.g. 30): " DISK_GB

# ---- Step 3: Privilege ----
PRIV_LEVEL=$(choose "Step 3: Container privilege level:" "Privileged" "Unprivileged")
[[ "$PRIV_LEVEL" == "Privileged" ]] && PRIV_OPT="--unprivileged 0" || PRIV_OPT="--unprivileged 1"

# ---- Step 4: Root password ----
info "Step 4: Set root password..."
while :; do
  read -rsp "Enter root password: " ROOTPW; echo
  read -rsp "Confirm root password: " ROOTPW2; echo
  [[ "$ROOTPW" == "$ROOTPW2" ]] && break
  warn "Passwords don't match, try again."
done

# ---- Step 5: Template discovery ----
info "Step 5: Discovering templates..."
if ! command -v jq >/dev/null 2>&1; then
  error "jq is required for template discovery."
  exit 1
fi

mapfile -t ALL_STORAGES < <(pvesm status | tail -n +2 | awk '{print $1}')
declare -A STORAGE_TEMPLATES
for st in "${ALL_STORAGES[@]}"; do
  templates=$(pvesh get /nodes/"$NODE"/storage/"$st"/content 2>/dev/null \
    | jq -r '.[] | select(.content=="vztmpl") | .volid' 2>/dev/null)
  [[ -n "$templates" ]] && STORAGE_TEMPLATES["$st"]="$templates"
done

mapfile -t TEMPLATE_STS < <(for k in "${!STORAGE_TEMPLATES[@]}"; do echo "$k"; done)
CHOSEN_ST=$(choose "Select storage that contains templates:" "${TEMPLATE_STS[@]}")
mapfile -t tmpl_options < <(echo "${STORAGE_TEMPLATES[$CHOSEN_ST]}")
CHOSEN_TEMPLATE=$(choose "Select template:" "${tmpl_options[@]}")

# ---- Step 6: Disk storage ----
CHOSEN_DISK_STORAGE=$(choose "Select storage for container disk:" "${ALL_STORAGES[@]}")
ROOTFS_ARG="${CHOSEN_DISK_STORAGE}:${DISK_GB}G"

# ---- Step 7: Bridge selection ----
mapfile -t BRIDGES < <(
  for br in /sys/class/net/*; do
    [[ -d "$br/bridge" ]] && [[ "$(basename "$br")" == vmbr* ]] && echo "$(basename "$br")"
  done
)
[[ ${#BRIDGES[@]} -eq 0 ]] && { error "No vmbr* bridges detected."; exit 1; }
CHOSEN_BRIDGE=$(choose "Select bridge:" "${BRIDGES[@]}")

# ---- Step 8: Create LXC ----
info "Step 8: Creating LXC container..."
pct create "$VMID" "$CHOSEN_TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --rootfs "$ROOTFS_ARG" \
  --net0 name=eth0,bridge="$CHOSEN_BRIDGE",ip=dhcp \
  $PRIV_OPT \
  --password "$ROOTPW"

pct start "$VMID"
success "Container $VMID started."

# ---- Step 9: Update & upgrade ----
info "Step 9: Updating & upgrading packages..."
pct exec "$VMID" -- bash -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get upgrade -y
" &
spinner $!
success "Packages updated."

# ---- Step 10: Enable root login ----
info "Step 10: Configuring SSH..."
pct exec "$VMID" -- bash -c "
  sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  (systemctl restart sshd || systemctl restart ssh || service ssh restart || true)
"
success "SSH configured."

# ---- Step 11: Display results ----
echo
success "Container created successfully!"
pct config "$VMID" | grep -i net0
mac=$(pct config "$VMID" | sed -n 's/.*hwaddr=\([^,]*\).*/\1/p')
[[ -n "$mac" ]] && echo "MAC Address: $mac"
info "Access container with: pct enter $VMID"
