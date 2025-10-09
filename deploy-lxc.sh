#!/usr/bin/env bash
# deploy-lxc.sh - LXC Creation Wrapper for Proxmox Cluster (PVE1 / PVE2)
# Place in /usr/local/sbin
# Must be run as root

# ---------- Root Check ----------
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

# ---------- Constants ----------
BASE_DIR="/usr/local/sbin/pvenode"
[[ -d "$BASE_DIR" ]] || mkdir -p "$BASE_DIR"

# ---------- Host Selection ----------
read -p "Run container creation on which host? (PVE1/PVE2): " TARGET
TARGET=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')

# Map hostnames to addresses
declare -A NODES=(
    [pve1]="10.1.1.200"
    [pve2]="10.1.1.210"
)

CURRENT_HOST=$(hostname | tr '[:upper:]' '[:lower:]')

if [[ -z "${NODES[$TARGET]}" ]]; then
    echo "Invalid selection. Choose PVE1 or PVE2."
    exit 1
fi

TARGET_IP=${NODES[$TARGET]}

# ---------- Remote Execution ----------
if [[ "$CURRENT_HOST" != "$TARGET" ]]; then
    echo "Executing on remote node $TARGET ($TARGET_IP)..."
    ssh -t root@"$TARGET_IP" "bash -s" <<'REMOTE_SCRIPT'
#!/usr/bin/env bash

# Change to script directory
BASE_DIR="/usr/local/sbin/pvenode"
cd "$BASE_DIR" || exit 1

declare VMID HOSTNAME CORES MEMORY DISKSIZE STORAGE BRIDGE TEMPLATE PRIVILEGE NESTING ROOTPASSWORD

# -------- Functions (Setup, VMID, Storage, Template, Bridge, Options, Create, Config) ----------
setup() {
    echo ""
    echo "==== Basic Setup ===="
    read -p "Enter hostname (eg: my-container): " HOSTNAME
    read -p "Enter CPU cores (eg: 2): " CORES
    read -p "Enter RAM in MB: " MEMORY
    read -p "Enter root disk size in GB: " DISKSIZE
}

vmid() {
    DEFAULT_VMID=$(pvesh get /cluster/nextid)
    read -p "Next available VMID is $DEFAULT_VMID. Press Enter to accept or type custom: " CUSTOM_VMID
    if [[ -z "$CUSTOM_VMID" ]]; then
        VMID="$DEFAULT_VMID"
        echo "Assigned VMID: $VMID"
    else
        while true; do
            if pvesh get /cluster/resources --type vm | awk '{print $2}' | grep -qw "$CUSTOM_VMID"; then
                echo "VMID $CUSTOM_VMID is already in use."
                read -p "Enter custom VMID: " CUSTOM_VMID
            elif [[ ! "$CUSTOM_VMID" =~ ^[0-9]+$ ]]; then
                echo "Invalid input. Please enter a numeric VMID."
                read -p "Enter custom VMID: " CUSTOM_VMID
            else
                VMID="$CUSTOM_VMID"
                echo "Using custom VMID: $VMID"
                break
            fi
        done
    fi
}

storage() {
    echo ""
    echo "==== Select Storage ===="
    options=($(pvesm status | awk '$2 ~ /dir|lvmthin|zfspool|btrfs|cephfs|rbd|nfs|cifs/ {print $1}'))
    if [ ${#options[@]} -eq 0 ]; then
        echo "No valid storage backends found."
        exit 1
    fi
    for i in "${!options[@]}"; do
        echo " $((i+1)). ${options[$i]}"
    done
    read -p "Select target [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        STORAGE=${options[$((choice-1))]}
        echo "Selected storage: $STORAGE"
    else
        echo "Invalid target."
        exit 1
    fi
}

template() {
    echo ""
    echo "==== Select Template ===="
    templates=()
    display=()
    for store in $(pvesm status --content vztmpl | awk 'NR>1 {print $1}'); do
        while read -r line; do
            tmpl_file=$(echo "$line" | awk '{print $1}')
            [[ -n "$tmpl_file" ]] && templates+=("$tmpl_file") && display+=("${tmpl_file%%.*}")
        done < <(pveam list "$store" | awk 'NR>1')
    done
    for i in "${!display[@]}"; do
        echo " [$i] ${display[$i]}"
    done
    read -p "Select template number: " choice
    TEMPLATE=${templates[$choice]}
    echo "Selected template: $TEMPLATE"
}

bridge() {
    echo ""
    echo "==== Select Network Bridge ===="
    bridges=()
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        [[ -d "$dev/bridge" ]] && bridges+=("$iface")
    done
    for i in "${!bridges[@]}"; do
        echo " [$((i+1))] ${bridges[$i]}"
    done
    if [[ ${#bridges[@]} -eq 1 ]]; then
        BRIDGE="--net0 name=eth0,bridge=${bridges[0]}"
        echo "Auto-selected bridge: $BRIDGE"
    else
        read -rp "Select a bridge [1-${#bridges[@]}]: " choice
        BRIDGE="name=eth0,bridge=${bridges[$((choice-1))]}"
        echo "Selected bridge: $BRIDGE"
    fi
}

options() {
    echo ""
    echo "==== Container Options ===="
    read -p "Privileged container? (y/n) [n]: " priv
    [[ "$priv" =~ ^[Yy]$ ]] && PRIVILEGE="0" || PRIVILEGE="1"
    read -p "Enable nesting? (y/n) [n]: " nest
    [[ "$nest" =~ ^[Yy]$ ]] && NESTING="1" || NESTING="0"
    while true; do
        read -s -p "Root password: " pass1; echo
        read -s -p "Confirm password: " pass2; echo
        [[ "$pass1" == "$pass2" && -n "$pass1" ]] && { ROOTPASSWORD="$pass1"; break; } || echo "Passwords do not match or empty."
    done
}

create() {
    echo ""
    echo "==== Review Configuration ===="
    echo "VMID      : $VMID"
    echo "hostname  : $HOSTNAME"
    echo "cores     : $CORES"
    echo "memory    : $MEMORY"
    echo "disk size : ${DISKSIZE}G"
    echo "storage   : $STORAGE"
    echo "bridge    : $BRIDGE"
    echo "template  : $TEMPLATE"
    echo "privileged: $PRIVILEGE"
    echo "nesting   : $NESTING"
    echo
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }

    pct create "$VMID" "$TEMPLATE" \
        -hostname "$HOSTNAME" \
        -cores "$CORES" \
        -memory "$MEMORY" \
        -rootfs "${STORAGE}:${DISKSIZE}" \
        -net0 "$BRIDGE" \
        -password "$ROOTPASSWORD" \
        -unprivileged "$PRIVILEGE" \
        -features nesting="$NESTING"

    [[ $? -eq 0 ]] && { echo "Starting container..."; pct start "$VMID"; } || { echo "Creation failed."; exit 1; }
}

config() {
    echo ""
    echo "==== Post-Configuration ===="
    pct exec "$VMID" -- bash -c "apt update && apt upgrade -y"
    pct exec "$VMID" -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec "$VMID" -- systemctl restart sshd
    pct exec "$VMID" -- rm -f /etc/update-motd.d/*
}

# -------- Execution ----------
setup
vmid
template
storage
bridge
options
create
config

REMOTE_SCRIPT
exit 0
fi

# ---------- Local Execution ----------
cd "$BASE_DIR" || exit 1
setup
vmid
template
storage
bridge
options
create
config
