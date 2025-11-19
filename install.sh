#!/bin/bash

# Resilient DNS Proxy - Manager (Install / Uninstall)
# Author: peterpt
# Co-Author: Google AI
# License: MIT

# --- VARIABLES ---
SOURCE_SCRIPT="./resilient_dns.py"
INSTALL_BIN="/usr/local/sbin/resilient-dns"
DATA_DIR="/usr/local/share/dns-proxy"
BACKUP_DIR="$DATA_DIR/backups"
DEPS_FILE="./requirements.txt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- HELPER FUNCTIONS ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[!] Please run as root (sudo).${NC}"
        exit 1
    fi
}

check_status() {
    if [ -f "$INSTALL_BIN" ]; then
        return 0 # Installed
    else
        return 1 # Not Installed
    fi
}

install_dependencies() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq python3 python3-pip
    fi

    if [ -f "$DEPS_FILE" ]; then
        pip3 install -r "$DEPS_FILE" --break-system-packages 2>/dev/null || pip3 install -r "$DEPS_FILE"
    else
        pip3 install dnslib dnspython --break-system-packages 2>/dev/null || pip3 install dnslib dnspython
    fi
}

do_install() {
    echo -e "${GREEN}>>> STARTING INSTALLATION <<<${NC}"
    
    if [ ! -f "$SOURCE_SCRIPT" ]; then
        echo -e "${RED}[!] Error: $SOURCE_SCRIPT not found in current folder.${NC}"
        exit 1
    fi

    # 1. Create Directories & Backup Folder
    mkdir -p "$DATA_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$DATA_DIR"

    # 2. BACKUP SYSTEM CONFIGS (Only if backup doesn't exist yet)
    echo -e "${YELLOW}[*] Backing up system configuration...${NC}"
    
    if [ ! -f "$BACKUP_DIR/resolv.conf.bak" ]; then
        if [ -f /etc/resolv.conf ]; then
            cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.bak"
            echo "    - Backed up resolv.conf"
        fi
    fi

    if [ ! -f "$BACKUP_DIR/dhclient.conf.bak" ]; then
        if [ -f /etc/dhcp/dhclient.conf ]; then
            cp /etc/dhcp/dhclient.conf "$BACKUP_DIR/dhclient.conf.bak"
            echo "    - Backed up dhclient.conf"
        fi
    fi

    # 3. Install Script
    install_dependencies
    echo -e "${YELLOW}[*] Deploying script...${NC}"
    cp "$SOURCE_SCRIPT" "$INSTALL_BIN"
    chmod +x "$INSTALL_BIN"

    # 4. Configure System DNS
    echo -e "${YELLOW}[*] Setting System DNS to 127.0.0.1...${NC}"
    echo "nameserver 127.0.0.1" > /etc/resolv.conf

    # 5. Configure DHCP Persistence
    if [ -d /etc/dhcp ]; then
        DHCP_CONF="/etc/dhcp/dhclient.conf"
        if [ -f "$DHCP_CONF" ]; then
            # Only add if not already there
            if ! grep -q "supersede domain-name-servers 127.0.0.1;" "$DHCP_CONF"; then
                echo "supersede domain-name-servers 127.0.0.1;" >> "$DHCP_CONF"
                echo "    - Added persistence to dhclient.conf"
            fi
        fi
    fi

    # 6. Create & Start Service
    echo -e "${YELLOW}[*] Configuring Service...${NC}"
    
    if pidof systemd > /dev/null || [ -d /run/systemd/system ]; then
        # SYSTEMD
        SERVICE_FILE="/etc/systemd/system/resilient-dns.service"
        cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Resilient DNS Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $INSTALL_BIN
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable resilient-dns
        systemctl restart resilient-dns
        echo "    - Systemd service started."
        
    else
        # SYSVINIT (DEVUAN)
        SERVICE_FILE="/etc/init.d/resilient-dns"
        cat << EOF > "$SERVICE_FILE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          resilient-dns
# Required-Start:    \$network \$local_fs \$remote_fs \$syslog
# Required-Stop:     \$network \$local_fs \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Resilient DNS Proxy
### END INIT INFO

DAEMON=/usr/bin/python3
SCRIPT=$INSTALL_BIN
NAME=resilient-dns
PIDFILE=/var/run/\$NAME.pid
LOGFILE=/var/log/\$NAME.log

case "\$1" in
  start)
    echo "Starting \$NAME..."
    if [ ! -f \$SCRIPT ]; then exit 1; fi
    # FIX: Escaped variables (\$PIDFILE, \$DAEMON) so they are written to the file
    start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE \\
    --startas /bin/sh -- -c "exec \$DAEMON \$SCRIPT >> \$LOGFILE 2>&1"
    ;;
  stop)
    echo "Stopping \$NAME..."
    start-stop-daemon --stop --pidfile \$PIDFILE
    rm -f \$PIDFILE
    ;;
  restart)
    \$0 stop
    sleep 1
    \$0 start
    ;;
  status)
    if [ -f \$PIDFILE ]; then echo "\$NAME is running."; else echo "\$NAME is stopped."; fi
    ;;
  *)
    echo "Usage: /etc/init.d/\$NAME {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
EOF
        chmod +x "$SERVICE_FILE"
        update-rc.d resilient-dns defaults
        service resilient-dns restart
        echo "    - SysVinit service started."
    fi

    echo ""
    echo -e "${GREEN}[✓] INSTALLATION COMPLETE!${NC}"
    echo -e "${CYAN}NOTE: Please disable 'DNS over HTTPS' in your Browser settings manually.${NC}"
}

do_uninstall() {
    echo -e "${RED}>>> STARTING UNINSTALLATION <<<${NC}"
    
    if ! check_status; then
        echo -e "${RED}[!] Not installed. Nothing to remove.${NC}"
        return
    fi

    # 1. Stop and Remove Service
    echo -e "${YELLOW}[*] Stopping service...${NC}"
    if pidof systemd > /dev/null || [ -d /run/systemd/system ]; then
        systemctl stop resilient-dns
        systemctl disable resilient-dns
        rm -f /etc/systemd/system/resilient-dns.service
        systemctl daemon-reload
    else
        service resilient-dns stop
        update-rc.d -f resilient-dns remove
        rm -f /etc/init.d/resilient-dns
    fi

    # 2. RESTORE SYSTEM CONFIGS
    echo -e "${YELLOW}[*] Restoring system configuration...${NC}"
    
    if [ -f "$BACKUP_DIR/resolv.conf.bak" ]; then
        cp "$BACKUP_DIR/resolv.conf.bak" /etc/resolv.conf
        echo "    - Restored original resolv.conf"
    else
        echo "    - No backup found. Setting DNS to 8.8.8.8 temporarily."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
    fi

    if [ -f "$BACKUP_DIR/dhclient.conf.bak" ]; then
        cp "$BACKUP_DIR/dhclient.conf.bak" /etc/dhcp/dhclient.conf
        echo "    - Restored original dhclient.conf"
    elif [ -f /etc/dhcp/dhclient.conf ]; then
        # Fallback: just remove our line if backup missing
        sed -i '/supersede domain-name-servers 127.0.0.1;/d' /etc/dhcp/dhclient.conf
        echo "    - Removed settings from dhclient.conf"
    fi

    # 3. Remove Files
    echo -e "${YELLOW}[*] Removing application files...${NC}"
    rm -f "$INSTALL_BIN"
    
    # Optional: Ask to keep data
    read -p "Do you want to delete the Phone Book (Stored IPs)? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR"
        echo "    - Data directory deleted."
    else
        echo "    - Data kept in $DATA_DIR"
    fi

    # 4. Restart Networking (to apply restored DNS)
    echo -e "${YELLOW}[*] Refreshing network state...${NC}"
    if command -v service &> /dev/null; then
        service networking restart 2>/dev/null || systemctl restart NetworkManager 2>/dev/null
    fi

    echo ""
    echo -e "${GREEN}[✓] UNINSTALL COMPLETE. System restored to default.${NC}"
}

# --- MAIN MENU ---

check_root

echo -e "${CYAN}---------------------------------------------${NC}"
echo -e "${CYAN}   Resilient DNS Proxy Manager               ${NC}"
echo -e "${CYAN}   Author: peterpt | Co-Author: Google AI    ${NC}"
echo -e "${CYAN}---------------------------------------------${NC}"

if check_status; then
    echo -e "Status: ${GREEN}INSTALLED${NC}"
    echo ""
    echo "1) Reinstall / Update"
    echo "2) Uninstall"
    echo "3) Exit"
    echo ""
    read -p "Select option [1-3]: " option
    case $option in
        1) do_install ;;
        2) do_uninstall ;;
        *) exit 0 ;;
    esac
else
    echo -e "Status: ${RED}NOT INSTALLED${NC}"
    echo ""
    echo "1) Install"
    echo "2) Exit"
    echo ""
    read -p "Select option [1-2]: " option
    case $option in
        1) do_install ;;
        *) exit 0 ;;
    esac
fi

  
  
