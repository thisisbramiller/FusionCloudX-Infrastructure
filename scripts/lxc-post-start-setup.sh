#!/usr/bin/env bash
# ==============================================================================
# LXC Post-Start Hook Script
# ==============================================================================
# This script runs ON THE PROXMOX HOST after an LXC container starts
# It installs required packages inside the container for Ansible management
# ==============================================================================

set -euo pipefail

# Get container ID from environment variable set by Proxmox
VMID="$1"
PHASE="$2"

# Only run during post-start phase
if [ "$PHASE" != "post-start" ]; then
    exit 0
fi

echo "[LXC Hook] Installing Ansible prerequisites in container $VMID..."

# Execute commands inside the container using pct exec
# Install sudo, python3, python3-pip, ssh-import-id
pct exec "$VMID" -- bash -c '
    # Update package cache
    apt-get update

    # Install required packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sudo \
        python3 \
        python3-pip \
        curl \
        wget \
        ca-certificates \
        gnupg

    # Clean up
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    # Create marker file
    echo "Ansible prerequisites installed via hook script" > /etc/ansible-ready
    echo "Installed: $(date)" >> /etc/ansible-ready
'

echo "[LXC Hook] Setup complete for container $VMID"
