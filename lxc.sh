#!/usr/bin/env bash
# Optimized Interactive LXC Creation Script for Proxmox VE with Countdown Waits
set -e

# ---------- Variables ----------
declare VMID HOSTNAME CORES MEMORY DISKSIZE STORAGE BRIDGE TEMPLATE PRIVILEGE NESTING ROOTPASSWORD

# ---------- Colors ----------
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"

# ---------- Functions ----------

countdown() {
    local seconds=$1
    echo -ne "${YELLOW}Waiting ${seconds} seconds: "
    for ((i=seconds; i>0; i--)); do
        echo -ne "$i "
        sleep 1
    done
    echo -e "${RESET}"
}

setup() {
    echo -e "\n==== Basic Setup ===="
    read -rp "Hostname (eg: my-container): " HOSTNAME
    read -rp "CPU cores (eg: 2): " CORES
    read -rp "Memory (MB): " MEMORY
    read -rp "Disk size (GB): " DISKSIZE
}

vmid() {
    local nextid custom
    nextid=$(pvesh get /cluster/nextid)
    read -rp "Next available VMID is ${nextid}. Press Enter to accept or specify custom: " custom

    while :; do
        if [[ -z "$custom" ]]; then
            VMID="$nextid"; break
        elif ! [[ "$custom" =~ ^[0-9]+$ ]]; then
            read -rp "Invalid VMID. Enter numeric value: " custom
        elif pvesh get /cluster/resources --type vm | awk '{print $2}' | grep -qw "$custom"; then
            read -rp "VMID already in use. Enter another: " custom
        else
            VMID="$custom"; break
        fi
    done
    echo -e "Using VMID: ${GREEN}$VMID${RESET}"
}

storage() {
    echo -e "\n==== Select Storage ===="
    mapfile -t options < <(pvesm status | awk '$2 ~ /dir|lvmthin|zfspool|btrfs|cephfs|rbd|nfs|cifs/ {print $1}')
    [[ ${#options[@]} -eq 0 ]] && { echo "No valid storage found."; exit 1; }

    for i in "${!options[@]}"; do
        echo " $((i+1)). ${options[$i]}"
    done

    read -rp "Select target [1-${#options[@]}]: " choice
    STORAGE=${options[$((choice-1))]:-}
    [[ -z "$STORAGE" ]] && { echo "Invalid choice."; exit 1; }
    echo -e "Selected storage: ${GREEN}$STORAGE${RESET}"
}

template() {
    echo -e "\n==== Select Template ===="
    mapfile -t templates < <(for s in $(pvesm status --content vztmpl | awk 'NR>1 {print $1}'); do pveam list "$s" | awk 'NR>1 {print $1}'; done)
    [[ ${#templates[@]} -eq 0 ]] && { echo "No templates found."; exit 1; }

    for i in "${!templates[@]}"; do
        echo " [$i] ${templates[$i]}"
    done

    read -rp "Select template number: " choice
    TEMPLATE=${templates[$choice]:-}
    [[ -z "$TEMPLATE" ]] && { echo "Invalid choice."; exit 1; }
    echo -e "Selected template: ${GREEN}$TEMPLATE${RESET}"
}

bridge() {
    echo -e "\n==== Select Network Bridge ===="
    mapfile -t bridges < <(for dev in /sys/class/net/*; do [[ -d "$dev/bridge" ]] && basename "$dev"; done)

    if [[ ${#bridges[@]} -eq 1 ]]; then
        BRIDGE="name=eth0,bridge=${bridges[0]},ip=dhcp"
        echo -e "Auto-selected bridge: ${GREEN}${bridges[0]}${RESET}"
    else
        for i in "${!bridges[@]}"; do
            echo " [$((i+1))] ${bridges[$i]}"
        done
        read -rp "Select bridge [1-${#bridges[@]}]: " choice
        BRIDGE="name=eth0,bridge=${bridges[$((choice-1))]},ip=dhcp"
        echo -e "Selected bridge: ${GREEN}${bridges[$((choice-1))]}${RESET}"
    fi
}

options() {
    echo -e "\n==== Container Options ===="
    read -rp "Privileged container? (y/n) [n]: " priv
    PRIVILEGE=$([[ "$priv" =~ ^[Yy]$ ]] && echo "0" || echo "1")

    read -rp "Enable nesting? (y/n) [n]: " nest
    NESTING=$([[ "$nest" =~ ^[Yy]$ ]] && echo "1" || echo "0")

    while :; do
        read -srp "Enter root password: " pass1; echo
        read -srp "Confirm root password: " pass2; echo
        [[ "$pass1" == "$pass2" && -n "$pass1" ]] && { ROOTPASSWORD="$pass1"; break; }
        echo "Passwords do not match or empty, try again."
    done
}

create() {
    echo -e "\n==== Review Configuration ===="
    cat <<EOF
VMID      : $VMID
Hostname  : $HOSTNAME
Cores     : $CORES
Memory    : ${MEMORY}MB
Disk Size : ${DISKSIZE}G
Storage   : $STORAGE
Bridge    : $BRIDGE
Template  : $TEMPLATE
Privileged: $PRIVILEGE
Nesting   : $NESTING
EOF

    read -rp "Proceed with container creation? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }

    echo -e "${YELLOW}Creating container...${RESET}"
    pct create "$VMID" "$TEMPLATE" \
        -hostname "$HOSTNAME" \
        -cores "$CORES" \
        -memory "$MEMORY" \
        -rootfs "${STORAGE}:${DISKSIZE}" \
        -net0 "$BRIDGE" \
        -password "$ROOTPASSWORD" \
        -unprivileged "$PRIVILEGE" \
        -features nesting="$NESTING"

    pct start "$VMID"
    echo -e "${GREEN}Container $VMID started.${RESET}"
    countdown 5
}

config() {
    echo -e "\n==== Post-Configuration ===="
    echo "Updating and installing base tools..."
    pct exec "$VMID" -- bash -c "
        set -e;
        export DEBIAN_FRONTEND=noninteractive;
        apt-get -yq update;
        apt-get -yq upgrade;
    "
    countdown 5

    pct exec "$VMID" -- bash -c "
        apt-get -yq install curl gnupg lsb-release ca-certificates apt-transport-https sudo;
        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config;
        systemctl restart sshd;
        rm -f /etc/update-motd.d/* /etc/update-motd.d/00-uname;
        : > /etc/motd
    "
    countdown 2

    if [[ -f /usr/local/sbin/pvenode/00-motd ]]; then
        pct push "$VMID" /usr/local/sbin/pvenode/00-motd /etc/update-motd.d/00-motd
        pct exec "$VMID" -- chmod +x /etc/update-motd.d/00-motd
        echo -e "Custom MOTD installed."
    else
        echo -e "${YELLOW}WARNING:${RESET} Custom MOTD not found."
    fi

    read -rp "Install Docker? (y/n): " docker
    if [[ "$docker" =~ ^[Yy]$ ]]; then
        pct exec "$VMID" -- bash -c "
            apt-get -yq update;
            apt-get -yq install apt-transport-https ca-certificates curl gnupg lsb-release sudo;
            source /etc/os-release;
            ARCH=\$(dpkg --print-architecture);
            CODENAME=\$(lsb_release -cs);
            curl -fsSL https://download.docker.com/linux/\$ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg;
            echo \"deb [arch=\$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/\$ID \$CODENAME stable\" > /etc/apt/sources.list.d/docker.list;
            apt-get -yq update;
            apt-get -yq install docker-ce docker-ce-cli containerd.io docker-compose-plugin;
        "
        countdown 5
        echo -e "${GREEN}Docker installed.${RESET}"

        read -rp "Install Portainer Agent? (y/n): " portainer
        if [[ "$portainer" =~ ^[Yy]$ ]]; then
            pct exec "$VMID" -- bash -c "
                mkdir -p /opt/agent;
                docker run -d -p 9001:9001 --name portainer_agent --restart=always \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v /opt/agent:/data \
                    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                    portainer/agent:latest
            "
            countdown 5
            echo -e "${GREEN}Portainer Agent installed.${RESET}"
        else
            echo "Skipped Portainer."
        fi
    else
        echo "Skipped Docker."
    fi

    echo "MAC address for eth0:"
    pct config "$VMID" | awk -F'[,=]' '/^net0:/ {for(i=1;i<=NF;i++) if($i~/hwaddr/) print $(i+1)}'
    echo -e "${GREEN}Post-configuration complete.${RESET}"
}

# ---------- Main ----------
setup
vmid
template
storage
bridge
options
create
config