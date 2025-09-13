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
declare VMID				#container ID
declare HOSTNAME		#container hostname
declare CORECOUNT		#container core count
declare MEMORY			#container memory (mb)
declare ROOTPW			#container password (root)
declare STORAGE			#container rootfs size
declare LOCATION		#container rootfs location
declare TEMPLATE		#container image template
declare MAC					#container mac address
declare PRIVLEVEL		#container privledge level
declare BRIDGE			#container bridge

# ---- HELPERS ----
# pick a templaye from all storage locations
pick_template() {
    echo -e "${CYAN}Scanning Proxmox for LXC templates...${RESET}"

    # Get all template images across all storages
    mapfile -t TEMPLATE_LIST < <(
        for STORAGE in $(pvesm status -content vz); do
            pvesm list "$STORAGE" --content vztmpl 2>/dev/null | awk '{print "'"$STORAGE"'/" $1}'
        done
    )

    if [ "${#TEMPLATE_LIST[@]}" -eq 0 ]; then
        echo -e "${RED}No LXC templates found on any storage.${RESET}"
        return 1
    fi

    # Display numbered list
    echo -e "${YELLOW}Available templates:${RESET}"
    for i in "${!TEMPLATE_LIST[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "${TEMPLATE_LIST[$i]}"
    done

    # Ask user to choose
    while :; do
        read -rp "Select a template by number: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TEMPLATE_LIST[@]} )); then
            TEMPLATE="${TEMPLATE_LIST[$((choice-1))]}"
            echo -e "${GREEN}You chose: $TEMPLATE${RESET}"
            break
        else
            echo -e "${RED}Invalid selection, try again.${RESET}"
        fi
    done
}


# ---- Gather Input ----
step_one() {
}

# ---- Create LXC ---- 
step_two() {
}

# ---- Clean up ----
step_three() {
}


# ---- Main thread ----
pick_template

