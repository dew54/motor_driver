#!/bin/bash

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VENV_DIR="venv"
PYTHON_MIN_VERSION="3.7"

echo -e "${GREEN}MAVLink Rover Environment Setup${NC}"
echo "================================"

# Check if Python3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python3 is not installed${NC}"
    echo "Install it with: sudo apt-get install python3 python3-pip python3-venv"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo -e "Detected Python version: ${GREEN}${PYTHON_VERSION}${NC}"

# Check if venv module is available
if ! python3 -c "import venv" &> /dev/null; then
    echo -e "${YELLOW}Warning: python3-venv not found${NC}"
    echo "Installing python3-venv..."
    sudo apt-get update
    sudo apt-get install -y python3-venv
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creating virtual environment in ./$VENV_DIR${NC}"
    python3 -m venv "$VENV_DIR"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create virtual environment${NC}"
        exit 1
    fi
    echo -e "${GREEN}Virtual environment created successfully${NC}"
else
    echo -e "${GREEN}Virtual environment already exists${NC}"
fi

# Activate virtual environment
echo -e "${YELLOW}Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to activate virtual environment${NC}"
    exit 1
fi

# Upgrade pip
echo -e "${YELLOW}Upgrading pip...${NC}"
pip install --upgrade pip

# Install dependencies
if [ -f "requirements.txt" ]; then
    echo -e "${YELLOW}Installing dependencies from requirements.txt...${NC}"
    pip install -r requirements.txt
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install dependencies${NC}"
        exit 1
    fi
    echo -e "${GREEN}Dependencies installed successfully${NC}"
else
    echo -e "${RED}Error: requirements.txt not found${NC}"
    exit 1
fi

# Check if we're on a Raspberry Pi
if [ -f "/proc/device-tree/model" ]; then
    PI_MODEL=$(cat /proc/device-tree/model)
    echo -e "${GREEN}Detected: ${PI_MODEL}${NC}"
    
    # Check if GPIO group exists and add user if needed
    if getent group gpio > /dev/null 2>&1; then
        if ! groups $USER | grep -q gpio; then
            echo -e "${YELLOW}Adding user to 'gpio' group for GPIO access...${NC}"
            sudo usermod -a -G gpio $USER
            echo -e "${YELLOW}You may need to log out and back in for group changes to take effect${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Warning: Not running on a Raspberry Pi${NC}"
    echo "RPi.GPIO will not function properly on this system"
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "To activate the environment in the future, run:"
echo -e "  ${GREEN}source $VENV_DIR/bin/activate${NC}"
echo ""
echo "To run the MAVLink node:"
echo -e "  ${GREEN}python3 mavlink_rover.py${NC}"
echo ""

# Keep the environment activated for the current shell
exec bash