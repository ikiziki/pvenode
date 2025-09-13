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
	echo "===== Set Host Specifications ====="
	read -p "Enter hostname (eg. skynet)" HOSTNAME
	read -p "Enter core count (eg. 2)" CORECOUNT
	read -p "Enter memory (eg. 2048)" MEMORY
	read -p "Enter disk size (eg. 30)" STORAGE
}

# pick a template from all storage locations
pick_template() {
	echo "TEMPLATE"
}

# pick a rootfs storage location
pick_storage() {
	echo "STORAGE"
}

# ---- Create LXC ---- 
create() {
	echo "CREATE"
}

# ---- Clean up ----
cleanup() {
	echo "CLEANUP"
}

# ---- Main thread ----
setup
pick_template
pick_storage
create
cleanup