#!/usr/bin/env bash
# create-lxc-interactive.sh
# Interactive LXC creator for Proxmox (robust version)

set -euo pipefail
NODE="$(hostname -s)"

# ---- Helper functions ----
choose() {
  prompt="$1"; shift
  options=("$@")
  while :; do
    echo
    echo "$prompt"
    for i in "${!options[@]}"; do
      printf "  %2d) %s\n" $((i+1)) "${options[$i]}"
    done
    read -rp "Choose [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return 0
    fi
    echo "Invalid choice."
  done
}

get_next_vmid() {
  nextid="$(pvesh get /cluster/nextid 2>/dev/null || true)"
  if [[ -n "$nextid" ]]; then echo "$nextid"; return; fi
  for id in $(seq 100 9999); do
    if ! pct status "$id" >/dev/null 2>&1 && ! qm status "$id" >/dev/null 2>&1; then
      echo "$id"; return
    fi
  done
  echo "ERROR: couldn't find free vmid" >&2
  exit 1
}

# ---- Start script ----
VMID="$(get_next_vmid)"
echo "Suggested VMID: $VMID"
read -rp "Use suggested VMID? [Y/n] " use_suggest
if [[ "$use_suggest" =~ ^[Nn] ]]; then
  read -rp "Enter VMID to use: " VMID
fi

read -rp "Hostname: " HOSTNAME
read -rp "Cores (e.g. 2): " CORES
read -rp "Memory in MB (e.g. 2048): " MEMORY
read -rp "Disk size in GB (e.g. 30): " DISK_GB

# ---- Privilege level ----
PRIV_LEVEL=$(choose "Container privilege level:" "Privileged" "Unprivileged")
[[ "$PRIV_LEVEL" == "Privileged" ]] && PRIV_OPT="--unprivileged 0" || PRIV_OPT="--unprivileged 1"

# ---- Root password ----
while :; do
  read -rsp "Enter root password: " ROOTPW; echo
  read -rsp "Confirm root password: " ROOTPW2; echo
  [[ "$ROOTPW" == "$ROOTPW2" ]] && break
  echo "Passwords don't match, try again."
done

# ---- Template discovery (JSON-safe) ----
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for template discovery. Install it first." >&2
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

# ---- Disk storage ----
CHOSEN_DISK_STORAGE=$(choose "Select storage for container disk:" "${ALL_STORAGES[@]}")
ROOTFS_ARG="${CHOSEN_DISK_STORAGE}:${DISK_GB}G"

# ---- Bridge selection (only vmbr*) ----
mapfile -t BRIDGES < <(
  for br in /sys/class/net/*; do
    [[ -d "$br/bridge" ]] && [[ "$(basename "$br")" == vmbr* ]] && echo "$(basename "$br")"
  done
)
if [[ ${#BRIDGES[@]} -eq 0 ]]; then
  echo "ERROR: No vmbr* bridges detected on this node." >&2
  exit 1
fi
CHOSEN_BRIDGE=$(choose "Select bridge:" "${BRIDGES[@]}")

# ---- Create LXC ----
echo "Creating LXC..."
pct create "$VMID" "$CHOSEN_TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --rootfs "$ROOTFS_ARG" \
  --net0 name=eth0,bridge="$CHOSEN_BRIDGE",ip=dhcp \
  $PRIV_OPT \
  --password "$ROOTPW"

pct start "$VMID"

# ---- Update & upgrade (non-interactive) ----
echo "Running apt update & upgrade..."
pct exec "$VMID" -- bash -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y && apt-get upgrade -y
"

# ---- Enable root login + password authentication ----
echo "Enabling root login + password authentication..."
pct exec "$VMID" -- bash -c "
  sed -i -E 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  (systemctl restart sshd || systemctl restart ssh || service ssh restart || true)
"

# ---- Display result ----
echo "Container created:"
pct config "$VMID" | grep -i net0
mac=$(pct config "$VMID" | sed -n 's/.*hwaddr=\([^,]*\).*/\1/p')
[[ -n "$mac" ]] && echo "MAC Address: $mac"
echo "You can access the container with: pct enter $VMID"