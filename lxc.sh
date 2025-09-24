#!/usr/bin/env bash
# A streamlined LXC creation script for Proxmox VE with colors and style

# ---------- Colors ----------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

print_info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
print_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
print_error()   { echo -e "${RED}[ERROR]${RESET} $*"; }
print_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
print_header()  { echo -e "\n${BOLD}${MAGENTA}==== $* ====${RESET}\n"; }

# ---------- Variables ----------
declare VMID HOSTNAME CORES MEMORY DISKSIZE STORAGE BRIDGE TEMPLATE PRIVILEGE NESTING ROOTPASSWORD

# ---------- Functions ----------
setup() {
    print_header "Basic Setup"
    read -p "${BOLD}Enter the hostname${RESET} (eg: my-container): " HOSTNAME
    read -p "${BOLD}Enter the number of CPU cores${RESET} (eg: 2): " CORES
    read -p "${BOLD}Enter the amount of RAM${RESET} (in MB): " MEMORY
    read -p "${BOLD}Enter the root disk size${RESET} (in GB): " DISKSIZE
}

vmid() {
    DEFAULT_VMID=$(pvesh get /cluster/nextid)
    read -p "${BOLD}Next available VMID${RESET} is $DEFAULT_VMID. Press Enter to accept or type a custom VMID: " CUSTOM_VMID

    if [[ -z "$CUSTOM_VMID" ]]; then
        VMID="$DEFAULT_VMID"
        print_success "Assigned VMID: $VMID"
    else
        while true; do
            if pvesh get /cluster/resources --type vm | awk '{print $2}' | grep -qw "$CUSTOM_VMID"; then
                print_error "VMID $CUSTOM_VMID is already in use."
                read -p "Enter custom VMID: " CUSTOM_VMID
            elif [[ ! "$CUSTOM_VMID" =~ ^[0-9]+$ ]]; then
                print_error "Invalid input. Please enter a numeric VMID."
                read -p "Enter custom VMID: " CUSTOM_VMID
            else
                VMID="$CUSTOM_VMID"
                print_success "Using custom VMID: $VMID"
                break
            fi
        done
    fi
}

storage() {
    print_header "Select Storage"
    options=($(pvesm status | awk '$2 ~ /dir|lvmthin|zfspool|btrfs|cephfs|rbd|nfs|cifs/ {print $1}'))

    if [ ${#options[@]} -eq 0 ]; then
        print_error "No valid storage backends found for container images."
        return 1
    fi

    for i in "${!options[@]}"; do
        echo -e " ${CYAN}$((i+1)).${RESET} ${options[$i]}"
    done

    read -p "Select target [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        STORAGE=${options[$((choice-1))]}
        print_success "Selected storage: $STORAGE"
    else
        print_error "Invalid target."
        return 1
    fi
}

template() {
    print_header "Select Template"
    templates=()
    display=()

    for store in $(pvesm status --content vztmpl | awk 'NR>1 {print $1}'); do
        while read -r line; do
            tmpl_file=$(echo "$line" | awk '{print $1}')
            if [[ -n "$tmpl_file" ]]; then
                templates+=("$tmpl_file")
                tmpl_name="${tmpl_file%%.*}"
                display+=("$tmpl_name")
            fi
        done < <(pveam list "$store" | awk 'NR>1')
    done

    for i in "${!display[@]}"; do
        echo -e " ${CYAN}[$i]${RESET} ${display[$i]}"
    done

    read -p "Select a template number: " choice
    TEMPLATE=${templates[$choice]}
    print_success "Selected template: $TEMPLATE"
}

bridge() {
    print_header "Select Network Bridge"
    bridges=()
    for dev in /sys/class/net/*; do
        iface=$(basename "$dev")
        if [[ -d "$dev/bridge" ]]; then
            bridges+=("$iface")
        fi
    done

    for i in "${!bridges[@]}"; do
        echo -e " ${CYAN}[$((i+1))]${RESET} ${bridges[$i]}"
    done

    if [[ ${#bridges[@]} -eq 1 ]]; then
        BRIDGE="--net0 name=eth0,bridge=${bridges[0]}"
        print_success "Auto-selected bridge: $BRIDGE"
    else
        read -rp "Select a bridge [1-${#bridges[@]}]: " choice
        BRIDGE="name=eth0,bridge=${bridges[$((choice-1))]}"
        print_success "Selected bridge: $BRIDGE"
    fi
}

options() {
    print_header "Container Options"
    read -p "Should the container be privileged? (y/n) [n]: " priv
    [[ "$priv" =~ ^[Yy]$ ]] && PRIVILEGE="0" || PRIVILEGE="1"

    read -p "Enable nesting? (y/n) [n]: " nest
    [[ "$nest" =~ ^[Yy]$ ]] && NESTING="1" || NESTING="0"

    while true; do
        read -s -p "Enter root password for container: " pass1; echo
        read -s -p "Confirm root password: " pass2; echo
        if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
            ROOTPASSWORD="$pass1"
            break
        else
            print_warn "Passwords do not match or are empty. Please try again."
        fi
    done
}

create() {
    print_header "Review Container Configuration"
    echo -e "${BOLD}VMID      :${RESET} $VMID"
    echo -e "${BOLD}hostname  :${RESET} $HOSTNAME"
    echo -e "${BOLD}cores     :${RESET} $CORES"
    echo -e "${BOLD}memory    :${RESET} $MEMORY"
    echo -e "${BOLD}disk size :${RESET} ${DISKSIZE}G"
    echo -e "${BOLD}storage   :${RESET} $STORAGE"
    echo -e "${BOLD}bridge    :${RESET} $BRIDGE"
    echo -e "${BOLD}template  :${RESET} $TEMPLATE"
    echo -e "${BOLD}privileged:${RESET} $PRIVILEGE"
    echo -e "${BOLD}nesting   :${RESET} $NESTING"
    echo

    read -p "Proceed with container creation? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warn "Container creation aborted."
        exit 1
    fi

    print_info "Creating container with VMID $VMID..."
    pct create "$VMID" "$TEMPLATE" \
        -hostname "$HOSTNAME" \
        -cores "$CORES" \
        -memory "$MEMORY" \
        -rootfs "${STORAGE}:${DISKSIZE}" \
        -net0 "$BRIDGE" \
        -password "$ROOTPASSWORD" \
        -unprivileged "$PRIVILEGE" \
        -features nesting="$NESTING"

    if [[ $? -eq 0 ]]; then
        print_success "Container $VMID created successfully."
    else
        print_error "Container creation failed."
        exit 1
    fi
}

config() {
    print_header "Post-Configuration"
    print_info "Configuring container with VMID $VMID..."

    pct exec "$VMID" -- bash -c "apt-get update && apt-get -y upgrade"
    pct exec "$VMID" -- sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec "$VMID" -- systemctl restart sshd
    pct exec "$VMID" -- rm -f /etc/update-motd.d/*

    read -p "Install Docker inside container $VMID? (y/n): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
        pct exec "$VMID" -- bash -c "apt-get install -y curl gnupg2 ca-certificates lsb-release"
        pct exec "$VMID" -- bash -c "curl -fsSL https://get.docker.com | sh"
        print_success "Docker installed on container $VMID."

        read -p "Install Portainer Agent inside container $VMID? (y/n): " install_portainer
        if [[ "$install_portainer" =~ ^[Yy]$ ]]; then
            pct exec "$VMID" -- mkdir -p /opt/agent
            pct exec "$VMID" -- docker run -d \
                -p 9001:9001 \
                --name portainer_agent \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /opt/agent:/data \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                portainer/agent:latest
            print_success "Portainer Agent installed on container $VMID."
        else
            print_warn "Skipped Portainer Agent installation."
        fi
    else
        print_warn "Skipped Docker installation."
    fi

    echo -e "${BOLD}Assigned MAC address for eth0:${RESET}"
    pct config "$VMID" | awk -F'[,=]' '/^net0:/ {for(i=1;i<=NF;i++) if($i~/hwaddr/) print $(i+1)}'
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