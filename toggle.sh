sh -c '
set -e

# Detect codename (Proxmox 9 = Debian 13 "trixie")
codename=$(lsb_release -sc 2>/dev/null || grep VERSION_CODENAME= /etc/os-release | cut -d= -f2)

# File paths
SRC_LIST="/etc/apt/sources.list"
PVE_ENTERPRISE_LIST="/etc/apt/sources.list.d/pve-enterprise.list"

# Backup directory
BACKUP_DIR="/etc/apt/repo-backups"
mkdir -p "$BACKUP_DIR"
timestamp=$(date +%Y%m%d-%H%M%S)

# Backup existing files if present
[ -f "$SRC_LIST" ] && cp "$SRC_LIST" "$BACKUP_DIR/sources.list.bak.$timestamp"
[ -f "$PVE_ENTERPRISE_LIST" ] && cp "$PVE_ENTERPRISE_LIST" "$BACKUP_DIR/pve-enterprise.list.bak.$timestamp"

echo "Configuring Proxmox VE 9 community (no-subscription) repository..."

# Disable enterprise repo if it exists
if [ -f "$PVE_ENTERPRISE_LIST" ]; then
    sed -i "s|^deb https://enterprise.proxmox.com|#deb https://enterprise.proxmox.com|" "$PVE_ENTERPRISE_LIST"
fi

# Ensure community repo line exists
if ! grep -q "download.proxmox.com" "$SRC_LIST" 2>/dev/null; then
    echo "deb https://download.proxmox.com/debian/pve $codename pve-no-subscription" >> "$SRC_LIST"
fi

# Ensure Debian security and updates (for Trixie)
if ! grep -q "security.debian.org" "$SRC_LIST"; then
    cat <<EOF >> "$SRC_LIST"

# Debian 13 (Trixie) security and updates
deb http://security.debian.org/debian-security $codename-security main contrib
deb http://deb.debian.org/debian $codename-updates main contrib
EOF
fi

# Fetch Proxmox 9 GPG key if missing
if [ ! -f /etc/apt/trusted.gpg.d/proxmox-release-9.gpg ]; then
    echo "🔑 Fetching Proxmox VE 9 GPG key..."
    wget -qO /etc/apt/trusted.gpg.d/proxmox-release-9.gpg https://enterprise.proxmox.com/debian/proxmox-release-9.gpg
fi

echo "✅ Proxmox 9 community repository configured."
echo "You can now run: apt update"
'