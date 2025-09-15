#!/usr/bin/env bash
# A streamlined LXC creation script for Proxmox VE


declare VMID
declare HOSTNAME
declare CORES
declare MEMORY
declare DISKSIZE
declare STORAGE
declare BRIDGE


# Function to gather basic setup info
setup() {
    read -p "Enter the hostname (eg: my-container): " HOSTNAME
    read -p "Enter the number of CPU cores (eg: 2): " CORES
    read -p "Enter the amount of RAM (in MB): " MEMORY
    read -p "Enter the root disk size (in GB): " DISKSIZE
}


# Function to get and confirm VMID
vmid() {
    # Get the next available VMID
    DEFAULT_VMID=$(pvesh get /cluster/nextid)

    # Prompt user (Enter = accept default)
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


# pick a storage location for the container image
storage() {
    # Get available storage backends that support container images
    options=($(pvesm status | awk '$2 ~ /dir|lvmthin|zfspool|btrfs|cephfs|rbd/ {print $1}'))

    if [ ${#options[@]} -eq 0 ]; then
        echo "No valid storage backends found for container images."
        return 1
    fi

    echo "Available storage backends:"
    for i in "${!options[@]}"; do
        echo "$((i+1)). ${options[$i]}"
    done

    # Prompt user
    read -p "Select storage [1-${#options[@]}]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        STORAGE="${options[$((choice-1))]}"
        echo "Selected storage: $STORAGE"
    else
        echo "Invalid choice."
        return 1
    fi
}


# pick a template for the container
template() {
    :
}


# pick a network bridge
bridge() {
    echo "Available network bridges:"
    bridges=()
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        if [[ -d "$dev/bridge" ]]; then
            bridges+=("$iface")
        fi
    done

    # show numbered list
    for i in "${!bridges[@]}"; do
        printf " [%d] %s\n" "$((i+1))" "${bridges[$i]}"
    done

    if [[ ${#bridges[@]} -eq 1 ]]; then
        BRIDGE=${bridges[0]}
        echo "Auto-selected bridge: $BRIDGE"
    else
        read -rp "Select a bridge [1-${#bridges[@]}]: " choice
        BRIDGE=${bridges[$((choice-1))]}
        echo "Selected bridge: $BRIDGE"
    fi
}


# create the container
create() {
    :
}


# configure the container
config() {
    :
}



# Main Loop
setup
vmid
template
storage
bridge
create
config

echo "Container $VMID ($HOSTNAME) created successfully with the following configuration:"

echo "hostname : $HOSTNAME"
echo "vmid     : $VMID"
echo "cores    : $CORES"
echo "memory   : $MEMORY"
echo "disk size: $DISKSIZE"
echo "storage  : $STORAGE"
echo "bridge   : $BRIDGE"