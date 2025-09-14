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

# ---- Gather Input ----
setup() {
    echo -e "${CYAN}${DIVIDER}${RESET}"
    echo -e "${CYAN}===== Set Host Specifications =====${RESET}"
    echo -e "${CYAN}${DIVIDER}${RESET}"
    
    read -p "$(echo -e ${YELLOW}Enter hostname (eg. skynet) : ${RESET})" HOSTNAME
    read -p "$(echo -e ${YELLOW}Enter core count (eg. 2) : ${RESET})" CORECOUNT
    read -p "$(echo -e ${YELLOW}Enter memory (eg. 2048) : ${RESET})" MEMORY
    read -p "$(echo -e ${YELLOW}Enter disk size (eg. 30) : ${RESET})" STORAGE

    echo -e "${GREEN}Host specifications saved!${RESET}"
}

# pick a template from all storage locations
pick_template() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Picking template...${RESET}"
}

# pick a rootfs storage location
pick_storage() {
    echo -e "${BLUE}${DIVIDER}${RESET}"
    echo -e "${BLUE}Picking storage location...${RESET}"
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
pick_template
pick_storage
create
cleanup