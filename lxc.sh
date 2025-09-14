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

# set a root password
set_pw() {
    local pw1 pw2

    while true; do
        # -s hides input
        read -s -p "$(echo -e "${YELLOW}Enter root password: ${RESET}")" pw1
        echo
        read -s -p "$(echo -e "${YELLOW}Confirm root password: ${RESET}")" pw2
        echo

        if [[ "$pw1" == "$pw2" && -n "$pw1" ]]; then
            ROOTPW="$pw1"
            echo -e "${GREEN}Password set successfully!${RESET}"
            break
        else
            echo -e "${RED}Passwords do not match or are empty, try again.${RESET}"
        fi
    done
}

# pick a vm id 
pick_vmid() {
    # List all existing VMIDs (LXC + QEMU)
    local used
    used=$(pvesh get /cluster/resources --type vm --output-format=json | jq -r '.[].vmid')

    # Find the next free VMID (starting from 100)
    local vmid=100
    while grep -qw "$vmid" <<< "$used"; do
        ((vmid++))
    done

    # Offer the user a choice to override
    echo -e "${YELLOW}Suggested next VMID is:${RESET} $vmid"
    read -rp $'\033[33mEnter VMID to use (or press Enter to accept suggested): \033[0m' input

    if [[ -n "$input" ]]; then
        # If user enters a VMID that is already in use, increment until free
        while grep -qw "$input" <<< "$used"; do
            echo -e "${YELLOW}VMID $input is already in use, incrementing...${RESET}"
            ((input++))
        done
        vmid=$input
    fi

    VMID=$vmid
    echo -e "${YELLOW}Using VMID:${RESET} $VMID"
}

# pick a template from all storage locations
pick_template() {
    local templates=()

    # Loop through all storages
    while read -r store _; do
        # Capture only valid template lines
        while read -r line; do
            local tmpl
            tmpl=$(echo "$line" | awk '{print $1}')
            [[ -n "$tmpl" ]] && templates+=("$store:$tmpl")
        done < <(pveam list "$store" 2>/dev/null | awk 'NR>1 {print}')
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

    # Collect storages that support rootdir
    while read -r store _; do
        storages+=("$store")
    done < <(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 {print $1}')

    # If none found, bail
    if [ ${#storages[@]} -eq 0 ]; then
        echo -e "${YELLOW}No storage locations with rootdir support found.${RESET}" >&2
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

    # Collect bridges (vmbr*) from network interfaces
    while read -r line; do
        local name
        name=$(echo "$line" | awk -F: '{print $2}' | xargs)  # strip spaces
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
    echo -e "${BLUE}Preparing to create LXC container...${RESET}"

    # Prompt for root password
    set_pw

    # Prompt for privilege level
    while true; do
        read -rp "$(echo -e "${YELLOW}Container type? (p=privileged / u=unprivileged) : ${RESET}")" choice
        case "$choice" in
            p|P)
                PRIVLEVEL="privileged"
                UNPRIV="0"
                break
                ;;
            u|U)
                PRIVLEVEL="unprivileged"
                UNPRIV="1"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Enter 'p' or 'u'.${RESET}"
                ;;
        esac
    done

    # Extract storage and template filename
    local store tmpl_file
    store="${TEMPLATE%%:*}"       # before the colon
    tmpl_file="${TEMPLATE#*:}"    # after the colon

    # Pretty print configuration
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${CYAN}Container Configuration:${RESET}"
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${YELLOW}VMID: ${RESET}$VMID"
    echo -e "${YELLOW}Hostname: ${RESET}$HOSTNAME"
    echo -e "${YELLOW}Cores: ${RESET}$CORECOUNT"
    echo -e "${YELLOW}Memory: ${RESET}$MEMORY MB"
    echo -e "${YELLOW}Disk: ${RESET}$STORAGE GB"
    echo -e "${YELLOW}Storage: ${RESET}$store"
    echo -e "${YELLOW}Template: ${RESET}$tmpl_file"
    echo -e "${YELLOW}Bridge: ${RESET}$BRIDGE"
    echo -e "${YELLOW}Type: ${RESET}$PRIVLEVEL"
    echo -e "${CYAN}${DIVIDER}${RESET}"

    # Confirm
    read -rp "$(echo -e "${YELLOW}Create this container? (y/n): ${RESET}")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Container creation cancelled.${RESET}"
        return 1
    fi

    # Create LXC container
    pct create "$VMID" "$store:$tmpl_file" \
        --hostname "$HOSTNAME" \
        --cores "$CORECOUNT" \
        --memory "$MEMORY" \
        --rootfs "${STORAGE}G" \
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
    fi
}

# ---- Clean up ----
cleanup() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Running post-creation cleanup and configuration...${RESET}"

    # Update and upgrade packages first
    echo -e "${YELLOW}Running apt update and upgrade...${RESET}"
    pct exec "$VMID" -- bash -c "apt update && apt upgrade -y"

    # Modify SSH config to allow root login and password auth
    echo -e "${YELLOW}Modifying SSH configuration...${RESET}"
    pct exec "$VMID" -- bash -c "sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config"
    pct exec "$VMID" -- bash -c "sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
    pct exec "$VMID" -- systemctl restart sshd

    # Clear /etc/update-motd.d/
    echo -e "${YELLOW}Clearing /etc/update-motd.d/ ...${RESET}"
    pct exec "$VMID" -- bash -c "rm -rf /etc/update-motd.d/*"

    # Ask user if they want Docker installed
    read -rp "$(echo -e ${YELLOW}Do you want to install Docker and Docker Compose? [y/N]: ${RESET})" install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installing Docker and Docker Compose...${RESET}"
        pct exec "$VMID" -- bash -c "apt install -y apt-transport-https ca-certificates curl gnupg lsb-release"
        pct exec "$VMID" -- bash -c "curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
        pct exec "$VMID" -- bash -c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list"
        pct exec "$VMID" -- bash -c "apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
        pct exec "$VMID" -- systemctl enable docker --now
        echo -e "${GREEN}Docker and Docker Compose installed successfully.${RESET}"
    fi

    # Print the MAC address of the container
    echo -e "${YELLOW}Fetching container MAC address...${RESET}"
    local mac
    mac=$(pct config "$VMID" | awk '/net0/ {print $2}' | sed 's/^.*hwaddr=//')
    echo -e "${GREEN}Container $VMID MAC address: ${RESET}$mac"

    echo -e "${GREEN}Cleanup and post-configuration complete.${RESET}"
}

# ---- Main thread ----
setup
pick_vmid
pick_template
pick_storage
pick_bridge
create
cleanup