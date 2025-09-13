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