#!/usr/bin/env bash
# A streamlined LXC creation script for Proxmox VE

declare VMID
declare HOSTNAME
declare CORES
declare MEMORY
declare DISKSIZE

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
    :
}

# pick a template for the container
template() {
    :
}

# pick a network bridge
bridge() {
    :
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

echo "LXC container $HOSTNAME created successfully!"
echo "You can start it with: pct start $VMID"
echo "Access it with: pct enter $VMID"