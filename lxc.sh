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
# pick a template from all storage locations
pick_template() {
    local STORAGE_DIRS
    local TEMPLATES=()
    local CHOICE

    # Get all directories under /var/lib/vz/template
    STORAGE_DIRS=(/var/lib/vz/template/*)

    # Collect template files
    for dir in "${STORAGE_DIRS[@]}"; do
        # Expand glob safely
        local files=( "$dir"/*.tar "$dir"/*.tar.gz "$dir"/*.tar.zst "$dir"/*.tar.xz )
        for tmpl in "${files[@]}"; do
            [ -f "$tmpl" ] && TEMPLATES+=("$tmpl")
        done
    done

    # Exit if no templates found
    if [ ${#TEMPLATES[@]} -eq 0 ]; then
        echo "No templates found in any storage."
        exit 1
    fi

    # Display numbered list for user
    echo "Available templates:"
    for i in "${!TEMPLATES[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "$(basename "${TEMPLATES[i]}")"
    done

    # Ask user to choose
    while :; do
        read -rp "Select a template number: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#TEMPLATES[@]}" ]; then
            break
        fi
        echo "Invalid selection, try again."
    done

    # Set TEMPLATE variable with full path
    TEMPLATE="${TEMPLATES[$((CHOICE-1))]}"
    echo "Selected template: $TEMPLATE"
}

# ---- Gather Input ----
step_one() {
    # Example: gather VMID, HOSTNAME, CORECOUNT, etc.
    :
}

# ---- Create LXC ---- 
step_two() {
    # Example: pct create command using $TEMPLATE
    :
}

# ---- Clean up ----
step_three() {
    # Example: any cleanup if creation fails
    :
}

# ---- Main thread ----
pick_template