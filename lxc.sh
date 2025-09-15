#!/usr/bin/env bash

# ==============================
# Colors
# ==============================
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

DIVIDER="======================================"

# ==============================
# Variables
# ==============================
declare VMID
declare HOSTNAME
declare CORECOUNT
declare MEMORY
declare ROOTPW
declare STORAGE
declare LOCATION
declare TEMPLATE_STORAGE
declare TEMPLATE_FILE
declare TEMPLATE_PATH
declare MAC
declare PRIVLEVEL
declare UNPRIV
declare BRIDGE

# ==============================
# Host Setup
# ==============================
setup() {
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${CYAN}===== Set Host Specifications =====${RESET}"
    echo -e "${CYAN}${DIVIDER}${RESET}"

    read -p "$(echo -e "${YELLOW}Enter hostname (eg. skynet): ${RESET}")" HOSTNAME
    read -p "$(echo -e "${YELLOW}Enter core count (eg. 2): ${RESET}")" CORECOUNT
    read -p "$(echo -e "${YELLOW}Enter memory (MB, eg. 2048): ${RESET}")" MEMORY
    read -p "$(echo -e "${YELLOW}Enter disk size (GB, eg. 30): ${RESET}")" STORAGE

    echo -e "${GREEN}Host specifications saved!${RESET}"
}

# ==============================
# Root Password
# ==============================
set_pw() {
    local pw1 pw2
    while true; do
        read -s -p "$(echo -e "${YELLOW}Enter root password: ${RESET}")" pw1; echo
        read -s -p "$(echo -e "${YELLOW}Confirm root password: ${RESET}")" pw2; echo
        if [[ "$pw1" == "$pw2" && -n "$pw1" ]]; then
            ROOTPW="$pw1"
            echo -e "${GREEN}Password set successfully!${RESET}"
            break
        else
            echo -e "${RED}Passwords do not match or are empty, try again.${RESET}"
        fi
    done
}

# ==============================
# VMID Selection
# ==============================
pick_vmid() {
    local used vmid input
    used=$(pvesh get /cluster/resources --type vm --output-format=json | jq -r '.[].vmid')
    vmid=100
    while grep -qw "$vmid" <<< "$used"; do ((vmid++)); done

    echo -e "${YELLOW}Suggested next VMID is:${RESET} $vmid"
    read -rp $'\033[33mEnter VMID to use (or press Enter to accept suggested): \033[0m' input

    if [[ -n "$input" ]]; then
        while grep -qw "$input" <<< "$used"; do
            echo -e "${YELLOW}VMID $input is already in use, incrementing...${RESET}"
            ((input++))
        done
        vmid=$input
    fi

    VMID=$vmid
    echo -e "${YELLOW}Using VMID:${RESET} $VMID"
}

# ==============================
# Template Selection (with full path)
# ==============================
pick_template() {
    local templates=()
    local display_names=()
    local store line tmpl_full tmpl_file

    while read -r store _; do
        while read -r line; do
            tmpl_full=$(echo "$line" | awk '{print $1}')
            [[ -z "$tmpl_full" ]] && continue
            tmpl_file="$tmpl_full"
            templates+=("$store:$tmpl_file")
            display_names+=("${tmpl_full##*/}")
        done < <(pveam list "$store" 2>/dev/null | awk 'NR>1 {print}')
    done < <(pvesm status | awk 'NR>1 {print $1}')

    if [ ${#templates[@]} -eq 0 ]; then
        echo -e "${RED}No LXC templates found in storage.${RESET}" >&2
        exit 1
    fi

    echo -e "${YELLOW}Select an LXC template:${RESET}"
    select choice in "${display_names[@]}"; do
        if [[ -n "$choice" ]]; then
            for i in "${!display_names[@]}"; do
                if [[ "${display_names[i]}" == "$choice" ]]; then
                    TEMPLATE_STORAGE="${templates[i]%%:*}"
                    TEMPLATE_FILE="${templates[i]#*:}"
                    # Convert STORAGE:vztmpl/file -> full path
                    TEMPLATE_PATH="/mnt/pve/${TEMPLATE_STORAGE}/${TEMPLATE_FILE}"
                    break
                fi
            done
            echo -e "${GREEN}Using template:${RESET} $TEMPLATE_PATH"
            return 0
        else
            echo -e "${RED}Invalid selection${RESET}" >&2
        fi
    done
}

# ==============================
# Storage Selection
# ==============================
pick_storage() {
    local storages=()
    local types=()
    while read -r line; do
        storages+=("$(echo "$line" | awk '{print $1}')")
        types+=("$(echo "$line" | awk '{print $2}')")
    done < <(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 {print}')

    if [ ${#storages[@]} -eq 0 ]; then
        echo -e "${RED}No storage locations with rootdir support found.${RESET}" >&2
        exit 1
    fi

    echo -e "${YELLOW}Select a storage location for the container disk:${RESET}"
    select choice in "${storages[@]}"; do
        if [[ -n "$choice" ]]; then
            LOCATION="$choice"
            STORAGE_TYPE="${types[REPLY-1]}"
            echo -e "${YELLOW}You selected:${RESET} $LOCATION ($STORAGE_TYPE)"
            return 0
        else
            echo -e "${RED}Invalid selection${RESET}" >&2
        fi
    done
}


# ==============================
# Bridge Selection
# ==============================
pick_bridge() {
    local bridges=()
    while read -r line; do
        local name
        name=$(echo "$line" | awk -F: '{print $2}' | xargs)
        [[ $name == vmbr* ]] && bridges+=("$name")
    done < <(ip -o link show)

    if [ ${#bridges[@]} -eq 0 ]; then
        echo -e "${RED}No network bridges found.${RESET}" >&2
        exit 1
    fi

    echo -e "${YELLOW}Select a network bridge:${RESET}"
    select choice in "${bridges[@]}"; do
        if [[ -n "$choice" ]]; then
            BRIDGE="$choice"
            echo -e "${YELLOW}You selected:${RESET} $BRIDGE"
            return 0
        else
            echo -e "${RED}Invalid selection${RESET}" >&2
        fi
    done
}

# ==============================
# Create LXC
# ==============================
create() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Preparing to create LXC container...${RESET}"

    set_pw

    # Privileged or unprivileged
    while true; do
        read -rp "$(echo -e "${YELLOW}Container type? (p=privileged / u=unprivileged): ${RESET}")" choice
        case "$choice" in
            p|P) PRIVLEVEL="privileged"; UNPRIV="0"; break ;;
            u|U) PRIVLEVEL="unprivileged"; UNPRIV="1"; break ;;
            *)   echo -e "${RED}Invalid choice. Enter 'p' or 'u'.${RESET}" ;;
        esac
    done

    # Summary
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${CYAN}Container Configuration:${RESET}"
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${YELLOW}VMID:     ${RESET}$VMID"
    echo -e "${YELLOW}Hostname: ${RESET}$HOSTNAME"
    echo -e "${YELLOW}Cores:    ${RESET}$CORECOUNT"
    echo -e "${YELLOW}Memory:   ${RESET}$MEMORY MB"
    echo -e "${YELLOW}Disk:     ${RESET}$STORAGE GB"
    echo -e "${YELLOW}Storage:  ${RESET}$LOCATION ($STORAGE_TYPE)"
    echo -e "${YELLOW}Template: ${RESET}$TEMPLATE_PATH"
    echo -e "${YELLOW}Bridge:   ${RESET}$BRIDGE"
    echo -e "${YELLOW}Type:     ${RESET}$PRIVLEVEL"
    echo -e "${CYAN}${DIVIDER}${RESET}"

    read -rp "$(echo -e "${YELLOW}Create this container? (y/n): ${RESET}")" confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "${RED}Cancelled.${RESET}"; return 1; }

    # Validate storage free space
    storage_info=$(pvesm status | awk -v s="$LOCATION" '$1==s {print $0}')
    if [[ -z "$storage_info" ]]; then
        echo -e "${RED}Storage $LOCATION not found.${RESET}"
        exit 1
    fi

    free_space=$(echo "$storage_info" | awk '{print $6}') # in GB
    if (( STORAGE > free_space )); then
        echo -e "${RED}Not enough free space on $LOCATION (requested: $STORAGE GB, free: $free_space GB).${RESET}"
        exit 1
    fi

    # Set ROOTFS depending on storage type
    if [[ "$STORAGE_TYPE" == "dir" ]]; then
        ROOTFS="${LOCATION}:${STORAGE}"
    elif [[ "$STORAGE_TYPE" == "lvmthin" ]]; then
        ROOTFS="${LOCATION}:${STORAGE}"
    else
        echo -e "${RED}Unsupported storage type: $STORAGE_TYPE${RESET}"
        exit 1
    fi
    echo -e "${YELLOW}Creating rootfs: ${RESET}$ROOTFS"

    # Create the container
    pct create "$VMID" "$TEMPLATE_PATH" \
        --hostname "$HOSTNAME" \
        --cores "$CORECOUNT" \
        --memory "$MEMORY" \
        --rootfs "$ROOTFS" \
        --net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
        --password "$ROOTPW" \
        --unprivileged "$UNPRIV" \
        --features nesting=1 \
        --onboot 1

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Container $VMID created successfully!${RESET}"
        pct start "$VMID"
        echo -e "${GREEN}Container started.${RESET}"
    else
        echo -e "${RED}Failed to create container.${RESET}"
        exit 1
    fi
}

# ==============================
# Post-creation Cleanup
# ==============================
cleanup() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Running post-creation cleanup and configuration...${RESET}"

    echo -e "${YELLOW}Running apt update and upgrade...${RESET}"
    pct exec "$VMID" -- bash -c "apt update && apt upgrade -y"

    echo -e "${YELLOW}Modifying SSH configuration...${RESET}"
    pct exec "$VMID" -- bash -c "sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config"
    pct exec "$VMID" -- bash -c "sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
    pct exec "$VMID" -- systemctl restart sshd

    echo -e "${YELLOW}Clearing /etc/update-motd.d/...${RESET}"
    pct exec "$VMID" -- bash -c "rm -rf /etc/update-motd.d/*"

    MAC=$(pct config "$VMID" | awk '/net0/ {print $2}' | sed 's/^.*hwaddr=//')
    echo -e "${GREEN}Container $VMID MAC address: ${RESET}$MAC"

    echo -e "${GREEN}Cleanup complete.${RESET}"
}

# ==============================
# Main
# ==============================
setup
pick_vmid
pick_template
pick_storage
pick_bridge
create
cleanup