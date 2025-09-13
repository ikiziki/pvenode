sh -c '
 set -e
 
 # Detect codename
 codename=$(lsb_release -sc 2>/dev/null || grep VERSION_CODENAME= /etc/os-release | cut -d= -f2)
 
 # File paths
 SRC_LIST="/etc/apt/sources.list"
 PVE_ENTERPRISE_LIST="/etc/apt/sources.list.d/pve-enterprise.list"
 
 # Backup directory
 BACKUP_DIR="/etc/apt/repo-backups"
 mkdir -p "$BACKUP_DIR"
 
 # Latest backup markers
 SRC_BAK="$BACKUP_DIR/sources.list.bak.latest"
 PVE_BAK="$BACKUP_DIR/pve-enterprise.list.bak.latest"
 
 # Make backups if they don’t already exist
 timestamp=$(date +%Y%m%d-%H%M%S)
 if [ ! -f "$SRC_BAK" ]; then
     [ -f "$SRC_LIST" ] && cp "$SRC_LIST" "$BACKUP_DIR/sources.list.bak.$timestamp" && cp "$SRC_LIST" "$SRC_BAK"
 fi
 if [ ! -f "$PVE_BAK" ]; then
     [ -f "$PVE_ENTERPRISE_LIST" ] && cp "$PVE_ENTERPRISE_LIST" "$BACKUP_DIR/pve-enterprise.list.bak.$timestamp" && cp "$PVE_ENTERPRISE_LIST" "$PVE_BAK"
 fi
 
 # Detect current mode
 if grep -q "^deb .*enterprise.proxmox.com" "$PVE_ENTERPRISE_LIST" 2>/dev/null; then
     # Currently enterprise → switch to community
     echo "Switching to community repos..."
     sed -i "s|^deb https://enterprise.proxmox.com|#deb https://enterprise.proxmox.com|" "$PVE_ENTERPRISE_LIST"
 
     if ! grep -q "^deb .*download.proxmox.com" "$SRC_LIST"; then
         echo "deb https://download.proxmox.com/debian/pve $codename pve-no-subscription" >> "$SRC_LIST"
     elif grep -q "^#deb .*download.proxmox.com" "$SRC_LIST"; then
         sed -i "s|^#deb https://download.proxmox.com|deb https://download.proxmox.com|" "$SRC_LIST"
     fi
     echo "✅ Community repo enabled."
 
 elif grep -q "^#deb .*enterprise.proxmox.com" "$PVE_ENTERPRISE_LIST" 2>/dev/null; then
     # Currently community → switch to enterprise
     echo "Switching to enterprise repos..."
     sed -i "s|^#deb https://enterprise.proxmox.com|deb https://enterprise.proxmox.com|" "$PVE_ENTERPRISE_LIST"
 
     # Comment out community repo if present
     sed -i "s|^deb https://download.proxmox.com|#deb https://download.proxmox.com|" "$SRC_LIST"
     echo "✅ Enterprise repo enabled."
 
 else
     echo "⚠ Could not detect current repo mode. Please check your sources files."
     exit 1
 fi
 '
