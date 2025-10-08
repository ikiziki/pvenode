#!/usr/bin/env bash
# LXC Creation Wrapper for Proxmox Cluster (PVE1 / PVE2)

# ---------- Host Selection ----------
read -p "Run container creation on which host? (PVE1/PVE2): " TARGET
TARGET=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]')

# Map hostnames to addresses (edit as needed)
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

# If running on selected host, execute directly
if [[ "$CURRENT_HOST" == "$TARGET" ]]; then
    echo "Running locally on $TARGET..."
else
    echo "Executing on remote node $TARGET ($TARGET_IP)..."
    ssh root@"$TARGET_IP" 'bash -s' <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
# --- Remote LXC Creation Script ---

declare VMID HOSTNAME CORES MEMORY DISKSIZE STORAGE BRIDGE TEMPLATE PRIVILEGE NESTING ROOTPASSWORD

setup() {
    echo ""
    echo "==== Basic Setup ===="
    read -p "Enter the hostname (eg: my-container): " HOSTNAME
    read -p "Enter the number of CPU cores (eg: 2): " CORES
    read -p "Enter the amount of RAM (in MB): " MEMORY
    read -p "Enter the root disk size (in GB): " DISKSIZE
}

vmid() {
    DEFAULT_VMID=$(pvesh get /cluster/nextid)
    read -p "Next available VMID is $DEFAULT_VMID. Press Enter to accept or type a custom VMID: " CUSTOM_VMID

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
        echo "No valid storage backends found for container images."
        return 1
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
        return 1
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
            if [[ -n "$tmpl_file" ]]; then
                templates+=("$tmpl_file")
                tmpl_name="${tmpl_file%%.*}"
                display+=("$tmpl_name")
            fi
        done < <(pveam list "$store" | awk 'NR>1')
    done

    for i in "${!display[@]}"; do
        echo " [$i] ${display[$i]}"
    done

    read -p "Select a template number: " choice
    TEMPLATE=${templates[$choice]}
    echo "Selected template: $TEMPLATE"
}

bridge() {
    echo ""
    echo "==== Select Network Bridge ===="
    bridges=()
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        if [[ -d "$dev/bridge" ]]; then
            bridges+=("$iface")
        fi
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
    read -p "Should the container be privileged? (y/n) [n]: " priv
    [[ "$priv" =~ ^[Yy]$ ]] && PRIVILEGE="0" || PRIVILEGE="1"

    read -p "Enable nesting? (y/n) [n]: " nest
    [[ "$nest" =~ ^[Yy]$ ]] && NESTING="1" || NESTING="0"

    while true; do
        read -s -p "Enter root password for container: " pass1; echo
        read -s -p "Confirm root password: " pass2; echo
        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            ROOTPASSWORD="$pass1"
            break
        else
            echo "Passwords do not match or are empty. Please try again."
        fi
    done
}

create() {
    echo ""
    echo "==== Review Container Configuration ===="
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

    read -p "Proceed with container creation? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }

    echo "Creating container $VMID..."
    pct create "$VMID" "$TEMPLATE" \
        -hostname "$HOSTNAME" \
        -cores "$CORES" \
        -memory "$MEMORY" \
        -rootfs "${STORAGE}:${DISKSIZE}" \
        -net0 "$BRIDGE" \
        -password "$ROOTPASSWORD" \
        -unprivileged "$PRIVILEGE" \
        -features nesting="$NESTING"

    if [[ $? -eq 0 ]]; then
        echo "Starting container..."
        pct start "$VMID"
    else
        echo "Container creation failed."
        exit 1
    fi
}

config() {
    echo ""
    echo "==== Post-Configuration ===="
    pct exec "$VMID" -- bash -c "apt update && apt upgrade -y"
    pct exec "$VMID" -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec "$VMID" -- systemctl restart sshd
    pct exec "$VMID" -- rm -f /etc/update-motd.d/*
}

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

# ---------- Local Execution Path ----------
setup
vmid
template
storage
bridge
options
create
config
