#!/bin/bash
# Proxmox Interactive Guest Creator
# Features: NAS-aware storage, privilege level, root password, auto-enable root SSH, actual MAC output

# Colors
GREEN="\e[32m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}=== Proxmox Interactive Guest Creator ===${RESET}"

# Prompt for VM or LXC
read -p "Create (1) VM or (2) LXC? [1/2]: " type

# Auto-select next free VMID
VMID=$(pvesh get /cluster/nextid)
echo -e "Next available ID: ${GREEN}$VMID${RESET}"
read -p "Use this VMID? [Y/n]: " ans
if [[ "$ans" =~ ^[Nn]$ ]]; then
    read -p "Enter VMID: " VMID
fi

# Common prompts
read -p "Name: " NAME
read -p "CPU cores: " CORES
read -p "Memory (MB): " MEMORY

# Disk storage selection (any storage that supports VM/LXC disks)
echo "Available storages for root disk:"
pvesm status | awk '$3 ~ /dir|lvm|zfspool/ {print NR-1 ") " $1 " (" $2 ")"}'
read -p "Select storage for root disk #: " diskidx
DISKSTORE=$(pvesm status | awk '$3 ~ /dir|lvm|zfspool/ {print $1}' | sed -n "${diskidx}p")

# Network bridge
echo "Available bridges:"
grep -o 'vmbr[0-9]\+' /etc/network/interfaces | sort -u | nl -w2 -s') '
read -p "Select bridge #: " bridx
BRIDGE=$(grep -o 'vmbr[0-9]\+' /etc/network/interfaces | sort -u | sed -n "${bridx}p")

if [[ "$type" == "2" ]]; then
    # LXC creation
    echo -e "${CYAN}--- LXC Setup ---${RESET}"
    
    read -p "Privilege level? (0 = unprivileged, 1 = root): " PRIVILEGE
    read -s -p "Set root password for LXC: " ROOTPASS
    echo

    # Template storage selection (only storages with content=vztmpl)
    echo "Available storages for LXC templates:"
    TMPL_STORES=$(pvesh get /storage | jq -r '.[] | select(.content | index("vztmpl")) | .storage')
    echo "$TMPL_STORES" | nl -w2 -s') '
    read -p "Select storage for template #: " tmplstoreidx
    TMPLSTORE=$(echo "$TMPL_STORES" | sed -n "${tmplstoreidx}p")

    echo "Available CT templates on $TMPLSTORE:"
    TEMPLATES=$(pvesm list $TMPLSTORE | awk '$2=="vztmpl"{print $1}' | nl -w2 -s') ')
    echo "$TEMPLATES"
    read -p "Select template #: " tmplidx
    TEMPLATE=$(pvesm list $TMPLSTORE | awk '$2=="vztmpl"{print $1}' | sed -n "${tmplidx}p")

    read -p "Disk size (e.g. 16G): " DISK

    pct create $VMID \
        $TMPLSTORE:vztmpl/$TEMPLATE \
        --hostname "$NAME" \
        --cores $CORES \
        --memory $MEMORY \
        --rootfs $DISKSTORE:$DISK \
        --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
        --password $ROOTPASS \
        --unprivileged $PRIVILEGE

    # Mount rootfs to enable root SSH login
    pct mount $VMID
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /var/lib/pve/lxc/$VMID/rootfs/etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /var/lib/pve/lxc/$VMID/rootfs/etc/ssh/sshd_config
    pct unmount $VMID

    # Output assigned MAC
    MAC=$(pct config $VMID | grep -i net0 | awk -F',' '{for(i=1;i<=NF;i++){if($i ~ /^hwaddr=/){split($i,a,"="); print a[2]}}}')
    echo -e "Assigned MAC address for LXC $VMID: ${GREEN}$MAC${RESET}"
    echo -e "${GREEN}LXC $VMID created! Root SSH login enabled.${RESET}"

elif [[ "$type" == "1" ]]; then
    # VM creation
    echo -e "${CYAN}--- VM Setup ---${RESET}"

    # ISO storage selection
    echo "Available storages for ISOs:"
    ISO_STORES=$(pvesh get /storage | jq -r '.[] | select(.content | index("iso")) | .storage')
    echo "$ISO_STORES" | nl -w2 -s') '
    read -p "Select storage for ISO #: " isoidx
    ISOSTORE=$(echo "$ISO_STORES" | sed -n "${isoidx}p")

    echo "Available ISOs on $ISOSTORE:"
    ISOS=$(pvesm list $ISOSTORE | awk '$2=="iso"{print $1}' | nl -w2 -s') ')
    echo "$ISOS"
    read -p "Select ISO #: " isoidx2
    ISO=$(pvesm list $ISOSTORE | awk '$2=="iso"{print $1}' | sed -n "${isoidx2}p")

    read -p "Disk size (e.g. 32G): " DISK
    read -s -p "Set root password for VM: " ROOTPASS
    echo

    qm create $VMID \
        --name "$NAME" \
        --cores $CORES \
        --memory $MEMORY \
        --net0 virtio,bridge=$BRIDGE \
        --scsihw virtio-scsi-pci \
        --scsi0 $DISKSTORE:$DISK \
        --boot order=scsi0 \
        --ide2 $ISOSTORE:iso/$ISO,media=cdrom \
        --ostype l26

    # Mount VM disk and enable root SSH login and set password before first boot
    VM_DISK_PATH=$(qm config $VMID | grep '^scsi0:' | awk -F':' '{print $2}')
    FULL_DISK_PATH=$(pvesm path $VM_DISK_PATH)

    modprobe nbd max_part=8
    qemu-nbd --connect=/dev/nbd0 $FULL_DISK_PATH

    # Detect root partition automatically
    ROOT_PART=$(lsblk -ln /dev/nbd0 | awk '$6=="part"{print $1; exit}')
    if [[ -z "$ROOT_PART" ]]; then
        echo "Error: Could not detect root partition on VM disk!"
        qemu-nbd --disconnect /dev/nbd0
        exit 1
    fi

    mkdir -p /mnt/vmroot
    mount /dev/$ROOT_PART /mnt/vmroot

    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /mnt/vmroot/etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /mnt/vmroot/etc/ssh/sshd_config

    # Set root password (hashed)
    HASHED_PASS=$(openssl passwd -6 "$ROOTPASS")
    chroot /mnt/vmroot /bin/bash -c "echo 'root:$HASHED_PASS' | chpasswd -e"

    umount /mnt/vmroot
    qemu-nbd --disconnect /dev/nbd0
    rmdir /mnt/vmroot

    # Output assigned MAC
    MAC=$(qm config $VMID | grep -i net0 | awk -F',' '{for(i=1;i<=NF;i++){if($i ~ /^hwaddr=/){split($i,a,"="); print a[2]}}}')
    echo -e "Assigned MAC address for VM $VMID: ${GREEN}$MAC${RESET}"
    echo -e "${GREEN}VM $VMID created! Root SSH login enabled.${RESET}"

else
    echo "Invalid choice"
fi
