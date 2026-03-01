#!/bin/bash
# Installation script for QGroundControl Video Streaming Service

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "QGC Video Streaming Service Installer"
echo -e "==========================================${NC}"

# Check if running as root for service installation
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}This script needs sudo for service installation${NC}"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"

echo ""
echo -e "${YELLOW}Step 1: Installing dependencies...${NC}"
apt update
apt install -y gstreamer1.0-tools \
               gstreamer1.0-plugins-base \
               gstreamer1.0-plugins-good \
               gstreamer1.0-plugins-bad \
               gstreamer1.0-libav \
               v4l-utils

echo ""
echo -e "${YELLOW}Step 2: Configuring QGC IP address...${NC}"
echo "Enter the IP address of your QGroundControl computer:"
read -p "QGC IP [192.168.1.100]: " QGC_IP
QGC_IP=${QGC_IP:-192.168.1.100}

echo "Using QGC IP: $QGC_IP"

# Update script with correct IP
sed -i "s/QGC_IP=\".*\"/QGC_IP=\"$QGC_IP\"/" "$SCRIPT_DIR/qgc-video-stream.sh"

echo ""
echo -e "${YELLOW}Step 3: Installing streaming script...${NC}"
cp "$SCRIPT_DIR/qgc-video-stream.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/qgc-video-stream.sh"
echo "Installed: $INSTALL_DIR/qgc-video-stream.sh"

# Update service file with correct script path
sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/qgc-video-stream.sh|" "$SCRIPT_DIR/qgc-video-stream.service"

# Update service file with correct user
ACTUAL_USER=$(logname 2>/dev/null || echo "pi")
sed -i "s/User=.*/User=$ACTUAL_USER/" "$SCRIPT_DIR/qgc-video-stream.service"

echo ""
echo -e "${YELLOW}Step 4: Installing systemd service...${NC}"
cp "$SCRIPT_DIR/qgc-video-stream.service" "$SERVICE_DIR/"
chmod 644 "$SERVICE_DIR/qgc-video-stream.service"
echo "Installed: $SERVICE_DIR/qgc-video-stream.service"

echo ""
echo -e "${YELLOW}Step 5: Creating log file...${NC}"
touch "$LOG_DIR/qgc-video-stream.log"
chown $ACTUAL_USER:$ACTUAL_USER "$LOG_DIR/qgc-video-stream.log"
echo "Created: $LOG_DIR/qgc-video-stream.log"

echo ""
echo -e "${YELLOW}Step 6: Reloading systemd...${NC}"
systemctl daemon-reload

echo ""
echo -e "${GREEN}=========================================="
echo "Installation Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Service commands:"
echo -e "  ${GREEN}Start streaming:${NC}    sudo systemctl start qgc-video-stream"
echo -e "  ${GREEN}Stop streaming:${NC}     sudo systemctl stop qgc-video-stream"
echo -e "  ${GREEN}Enable at boot:${NC}     sudo systemctl enable qgc-video-stream"
echo -e "  ${GREEN}Disable at boot:${NC}    sudo systemctl disable qgc-video-stream"
echo -e "  ${GREEN}Check status:${NC}       sudo systemctl status qgc-video-stream"
echo -e "  ${GREEN}View logs:${NC}          sudo journalctl -u qgc-video-stream -f"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Configure QGroundControl to receive video on UDP port 5600"
echo "2. Start the service: sudo systemctl start qgc-video-stream"
echo "3. (Optional) Enable auto-start: sudo systemctl enable qgc-video-stream"
echo ""