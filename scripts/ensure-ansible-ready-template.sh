#!/usr/bin/env bash
# ==============================================================================
# Ensure Ansible-Ready LXC Template Exists
# ==============================================================================
# Idempotent script that checks if template exists and creates it if missing
# Safe to run multiple times
# ==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
TEMPLATE_ID=9000
TEMPLATE_NAME="debian-12-ansible-ready"
BASE_TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
STORAGE="vm-data"
TEMPLATE_STORAGE="nas-infrastructure"
TEMPLATE_FILE="/var/lib/vz/template/cache/${TEMPLATE_NAME}.tar.zst"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  Ensuring Ansible-Ready LXC Template${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Check if template already exists
if [ -f "$TEMPLATE_FILE" ]; then
    echo -e "${GREEN}✓ Template already exists: $TEMPLATE_FILE${NC}"
    echo "  No action needed"
    exit 0
fi

echo -e "${BLUE}Template not found, creating...${NC}"
echo ""

# Check if we're on Proxmox
if ! command -v pct &> /dev/null; then
    echo -e "${RED}Error: This script must be run on a Proxmox host${NC}"
    exit 1
fi

# Check if temporary container ID is already in use
if pct status $TEMPLATE_ID &>/dev/null; then
    echo -e "${RED}Error: Container ID $TEMPLATE_ID already exists${NC}"
    echo "  Please delete it first: pct destroy $TEMPLATE_ID"
    exit 1
fi

echo -e "${BLUE}Step 1: Creating temporary container from base Debian template...${NC}"

# Create temporary container
pct create $TEMPLATE_ID \
    $TEMPLATE_STORAGE:vztmpl/$BASE_TEMPLATE \
    --hostname $TEMPLATE_NAME \
    --cores 2 \
    --memory 1024 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --storage $STORAGE \
    --unprivileged 1

echo -e "${GREEN}✓ Container created${NC}"

echo -e "${BLUE}Step 2: Starting container...${NC}"
pct start $TEMPLATE_ID
sleep 5

echo -e "${GREEN}✓ Container started${NC}"

echo -e "${BLUE}Step 3: Installing required packages...${NC}"

# Install packages
pct exec $TEMPLATE_ID -- bash -c '
    set -euo pipefail

    # Update package cache
    apt-get update

    # Install required packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sudo \
        python3 \
        python3-pip \
        ssh-import-id \
        curl \
        wget \
        ca-certificates \
        gnupg

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*
'

echo -e "${GREEN}✓ Packages installed${NC}"

echo -e "${BLUE}Step 4: Configuring container for template use...${NC}"

pct exec $TEMPLATE_ID -- bash -c '
    # Remove SSH host keys (will be regenerated on first boot)
    rm -f /etc/ssh/ssh_host_*

    # Remove machine-id (will be regenerated)
    truncate -s 0 /etc/machine-id
    rm -f /var/lib/dbus/machine-id

    # Clear bash history
    history -c
    rm -f /root/.bash_history

    # Clear logs
    find /var/log -type f -exec truncate -s 0 {} \;

    # Create marker file
    echo "Ansible-ready LXC template" > /etc/ansible-ready
    echo "Created: $(date)" >> /etc/ansible-ready
    echo "Packages: sudo, python3, python3-pip, ssh-import-id" >> /etc/ansible-ready
'

echo -e "${GREEN}✓ Container configured${NC}"

echo -e "${BLUE}Step 5: Stopping container...${NC}"
pct stop $TEMPLATE_ID
sleep 3

echo -e "${GREEN}✓ Container stopped${NC}"

echo -e "${BLUE}Step 6: Converting to template...${NC}"

# Create backup as template
vzdump $TEMPLATE_ID \
    --storage $TEMPLATE_STORAGE \
    --mode stop \
    --compress zstd \
    --dumpdir /var/lib/vz/template/cache

# Rename backup to template format
BACKUP=$(ls -t /var/lib/vz/dump/vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1)
mv "$BACKUP" "$TEMPLATE_FILE"

echo -e "${GREEN}✓ Template created: $TEMPLATE_FILE${NC}"

echo -e "${BLUE}Step 7: Cleaning up temporary container...${NC}"
pct destroy $TEMPLATE_ID

echo -e "${GREEN}✓ Cleanup complete${NC}"

echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}  Template Creation Complete!${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
echo -e "${BLUE}Template Details:${NC}"
echo "  Name: $TEMPLATE_NAME"
echo "  File: $TEMPLATE_FILE"
echo "  Location: $TEMPLATE_STORAGE"
echo ""
