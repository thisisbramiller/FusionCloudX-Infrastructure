#!/usr/bin/env bash
# ==============================================================================
# Create Ansible-Ready LXC Template for Proxmox
# ==============================================================================
# This script creates a custom Debian 12 LXC template with packages pre-installed
# for Ansible management: sudo, python3, python3-pip, ssh-import-id
#
# USAGE: Run this on the Proxmox host
# ==============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  Creating Ansible-Ready LXC Template${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Configuration
TEMPLATE_ID=9000
TEMPLATE_NAME="debian-12-ansible-ready"
BASE_TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
STORAGE="vm-data"
TEMPLATE_STORAGE="nas-infrastructure"

# Check if we're on Proxmox
if ! command -v pct &> /dev/null; then
    echo -e "${RED}Error: This script must be run on a Proxmox host${NC}"
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

# Convert to template
# Note: pct doesn't have native template conversion like qemu VMs
# We'll create a backup and use it as a template

BACKUP_FILE="/var/lib/vz/template/cache/${TEMPLATE_NAME}.tar.zst"

# Create backup as template
vzdump $TEMPLATE_ID \
    --storage $TEMPLATE_STORAGE \
    --mode stop \
    --compress zstd \
    --dumpdir /var/lib/vz/template/cache

# Rename backup to template format
BACKUP=$(ls -t /var/lib/vz/dump/vzdump-lxc-${TEMPLATE_ID}-*.tar.zst | head -1)
mv "$BACKUP" "$BACKUP_FILE"

echo -e "${GREEN}✓ Template created: $BACKUP_FILE${NC}"

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
echo "  File: $BACKUP_FILE"
echo "  Location: $TEMPLATE_STORAGE"
echo ""
echo -e "${BLUE}Included Packages:${NC}"
echo "  - sudo (for Ansible privilege escalation)"
echo "  - python3 (for Ansible modules)"
echo "  - python3-pip (for Python dependencies)"
echo "  - ssh-import-id (for GitHub SSH key import)"
echo "  - curl, wget, ca-certificates, gnupg (utilities)"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Update terraform/variables.tf to use this template"
echo "  2. Update terraform/lxc-postgresql.tf template reference"
echo "  3. Run terraform apply"
echo ""
