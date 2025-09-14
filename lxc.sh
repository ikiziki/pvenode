#!/usr/bin/env bash

# ---- Colors ----
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---- Divider ----
DIVIDER="======================================"

# ---- Variables ----
declare VMID        # container ID
declare HOSTNAME    # container hostname
declare CORECOUNT   # container core count
declare MEMORY      # container memory (MB)
declare ROOTPW      # container password (root)
declare STORAGE     # container rootfs size
declare LOCATION    # container rootfs location
declare TEMPLATE    # container image template
declare MAC         # container MAC address
declare PRIVLEVEL   # container privilege level
declare BRIDGE      # container bridge

# ---- HELPERS ----
# ---- Gather Input ----
setup() {
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${CYAN}===== Set Host Specifications =====${RESET}"
    echo -e "${CYAN}${DIVIDER}${RESET}"

    read -p "$(echo -e "${YELLOW}Enter hostname (eg. skynet) : ${RESET}")" HOSTNAME
    read -p "$(echo -e "${YELLOW}Enter core count (eg. 2) : ${RESET}")" CORECOUNT
    read -p "$(echo -e "${YELLOW}Enter memory (eg. 2048) : ${RESET}")" MEMORY
    read -p "$(echo -e "${YELLOW}Enter disk size (eg. 30) : ${RESET}")" STORAGE

    echo -e "${GREEN}Host specifications saved!${RESET}"
}

# pick a vm id 
pick_vmid() {
    # List all existing VMIDs (LXC + QEMU)
    local used
    used=$(pvesh get /cluster/resources --type vm --output-format=json | jq -r '.[].vmid')

    # Find the next free VMID (starting from 100)
    local vmid=100
    while [[ " ${used[*]} " =~ " $vmid " ]]; do
        ((vmid++))
    done

    # Offer the user a choice to override
    echo -e "${YELLOW}Suggested next VMID is:${RESET} $vmid"
    read -rp "$(echo -e ${YELLOW}Enter VMID to use (or press Enter to accept suggested): ${RESET})" input
    if [[ -n "$input" ]]; then
        if [[ " ${used[*]} " =~ " $input " ]]; then
            echo -e "${YELLOW}Warning: VMID $input is already in use. Using suggested $vmid instead.${RESET}"
        else
            vmid=$input
        fi
    fi

    VMID=$vmid
    echo -e "${YELLOW}Using VMID:${RESET} $VMID"
}

# pick a template from all storage locations
pick_template() {
    local templates=()

    # Collect templates across all storages
    while read -r store _; do
        while read -r line; do
            local tmpl
            tmpl=$(echo "$line" | awk '{print $1}')   # <-- first column is the filename
            [[ -n "$tmpl" ]] && templates+=("$store:$tmpl")
        done < <(pveam list "$store" | awk 'NR>1 {print}')
    done < <(pvesm status | awk 'NR>1 {print $1}')

    # If none found, bail
    if [ ${#templates[@]} -eq 0 ]; then
        echo -e "${YELLOW}No LXC templates found.${RESET}" >&2
        return 1
    fi

    # Menu
    echo -e "${YELLOW}Select an LXC template:${RESET}"
    select choice in "${templates[@]}"; do
        if [[ -n "$choice" ]]; then
            TEMPLATE="$choice"
            echo -e "${YELLOW}You selected:${RESET} $TEMPLATE"
            return 0
        else
            echo -e "${YELLOW}Invalid selection${RESET}" >&2
        fi
    done
}

# pick a rootfs storage location
pick_storage() {
    local storages=()

    # Collect storage IDs from pvesm
    while read -r store _; do
        storages+=("$store")
    done < <(pvesm status | awk 'NR>1 {print $1}')

    # If none found, bail
    if [ ${#storages[@]} -eq 0 ]; then
        echo -e "${YELLOW}No storage locations found.${RESET}" >&2
        return 1
    fi

    # Menu
    echo -e "${YELLOW}Select a storage location:${RESET}"
    select choice in "${storages[@]}"; do
        if [[ -n "$choice" ]]; then
            LOCATION="$choice"
            echo -e "${YELLOW}You selected:${RESET} $LOCATION"
            return 0
        else
            echo -e "${YELLOW}Invalid selection${RESET}" >&2
        fi
    done
}

# pick a network bridge for the new host
pick_bridge() {
    local bridges=()

    # Collect bridges (vmbr*) from network config
    while read -r line; do
        local name
        name=$(echo "$line" | awk -F: '{print $1}')
        [[ $name == vmbr* ]] && bridges+=("$name")
    done < <(ip -o link show)

    # If none found, bail
    if [ ${#bridges[@]} -eq 0 ]; then
        echo -e "${YELLOW}No bridges found.${RESET}" >&2
        return 1
    fi

    # Menu
    echo -e "${YELLOW}Select a network bridge:${RESET}"
    select choice in "${bridges[@]}"; do
        if [[ -n "$choice" ]]; then
            BRIDGE="$choice"
            echo -e "${YELLOW}You selected:${RESET} $BRIDGE"
            return 0
        else
            echo -e "${YELLOW}Invalid selection${RESET}" >&2
        fi
    done
}

# ---- Create LXC ---- 
create() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Creating LXC container...${RESET}"
}

# ---- Clean up ----
cleanup() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Cleaning up temporary files...${RESET}"
}

# ---- Main thread ----
setup
pick_vmid
pick_template
pick_storage
pick_bridge
create
cleanup