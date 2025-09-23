#!/usr/bin/env bash
# A streamlined LXC creation script for Proxmox VE

declare VMID
declare HOSTNAME
declare CORES
declare MEMORY
declare DISKSIZE
declare STORAGE
declare BRIDGE
declare TEMPLATE
declare PRIVILEGE
declare NESTING
declare ROOTPASSWORD

# Function to gather basic setup info
setup() {
    read -p "Enter the hostname (eg: my-container): " HOSTNAME
    read -p "Enter the number of CPU cores (eg: 2): " CORES
    read -p "Enter the amount of RAM (in MB): " MEMORY
    read -p "Enter the root disk size (in GB): " DISKSIZE
}

# Function to get and confirm VMID
vmid() {
    DEFAULT_VMID=$(pvesh get /cluster/nextid)
    read -p "Next available VMID is $DEFAULT_VMID. Press Enter to accept or type a custom VMID: " CUSTOM_VMID

    if [[ -z "$CUSTOM_VMID" ]]; then
        VMID="$DEFAULT_VMID"
        echo "Assigned VMID: $VMID"
    else
        while true; do
            if pvesh get /cluster/resources --type vm | awk '{print $2}' | grep -qw "$CUSTOM_VMID"; then
                echo "Error: VMID $CUSTOM_VMID is already in use. Try again."
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

# Pick a storage location for the container image
storage() {
    options=($(pvesm status | awk '$2 ~ /dir|lvmthin|zfspool|btrfs|cephfs|rbd|nfs|cifs/ {print $1}'))


    if [ ${#options[@]} -eq 0 ]; then
        echo "No valid storage backends found for container images."
        return 1
    fi

    echo "Available storage targets:"
    for i in "${!options[@]}"; do
        echo "$((i+1)). ${options[$i]}"
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

# Pick a template for the container
template() {
    echo "Scanning for available container templates:"

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
        echo "[$i] ${display[$i]}"
    done

    read -p "Select a template number: " choice
    TEMPLATE=${templates[$choice]}
    echo "Selected template: $TEMPLATE"
}

# Pick a network bridge
bridge() {
    echo "Available network bridges:"
    bridges=()
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        if [[ -d "$dev/bridge" ]]; then
            bridges+=("$iface")
        fi
    done

    for i in "${!bridges[@]}"; do
        printf " [%d] %s\n" "$((i+1))" "${bridges[$i]}"
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

# set container options
options() {
    read -p "Should the container be privileged? (y/n) [n]: " priv
    if [[ "$priv" =~ ^[Yy]$ ]]; then
        PRIVILEGE="0"
    else
        PRIVILEGE="1"
    fi

    read -p "Enable nesting? (y/n) [n]: " nest
    if [[ "$nest" =~ ^[Yy]$ ]]; then
        NESTING="1"
    else
        NESTING="0"
    fi

    while true; do
        read -s -p "Enter root password for container: " pass1
        echo
        read -s -p "Confirm root password: " pass2
        echo
        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            ROOTPASSWORD="$pass1"
            break
        else
            echo "Passwords do not match or are empty. Please try again."
        fi
    done
}

# Create the container
create() {
    echo
    echo "================================================="
    echo " Review container configuration:"
    echo "================================================="
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
    echo "================================================="
    echo

    read -p "Proceed with container creation? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Container creation aborted."
        exit 1
    fi

    echo "Creating container with VMID $VMID..."
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
        echo "Container $VMID created successfully."
    else
        echo "Error: Container creation failed."
        exit 1
    fi
}

# Configure the container
config() {
    echo "Configuring container with VMID $VMID..."

    # Update and upgrade packages first
    pct exec "$VMID" -- bash -c "apt-get update && apt-get -y upgrade"

    # Enable root SSH login
    pct exec "$VMID" -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec "$VMID" -- systemctl restart sshd

    # Clear /etc/update-motd.d
    pct exec "$VMID" -- rm -f /etc/update-motd.d/*

    # Ask about Docker
    read -p "Install Docker inside container $VMID? (y/n): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        pct exec "$VMID" -- bash -c "apt-get install -y curl gnupg2 ca-certificates lsb-release"
        pct exec "$VMID" -- bash -c "curl -fsSL https://get.docker.com | sh"
        echo "Docker installed on container $VMID."

        # Ask about Portainer Agent
        read -p "Install Portainer Agent inside container $VMID? (y/n): " install_portainer
        if [[ "$install_portainer" =~ ^[Yy]$ ]]; then
            pct exec "$VMID" -- mkdir -p /opt/agent
            pct exec "$VMID" -- docker run -d \
                -p 9001:9001 \
                --name portainer_agent \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /opt/agent:/data \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                portainer/agent:latest
            echo "Portainer Agent installed on container $VMID (bind-mounted to /opt/agent, listening on port 9001)."
        else
            echo "Skipped Portainer Agent installation."
        fi
    else
        echo "Skipped Docker installation (Portainer Agent requires Docker)."
    fi

    # Print MAC address of container interface
    echo "Assigned MAC address for eth0 in container $VMID:"
    pct config "$VMID" | awk -F'[,=]' '/^net0:/ {for(i=1;i<=NF;i++) if($i~/hwaddr/) print $(i+1)}'
}


# Main Loop
setup
vmid
template
storage
bridge
options
create
config
