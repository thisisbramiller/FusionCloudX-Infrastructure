#!/bin/bash
# ==============================================================================
# Provision Script: Ansible-Ready LXC Template
# ==============================================================================
# Installs Ansible prerequisites into a Debian 12 LXC container
# Run by Packer during template build
#
# Packages installed:
#   - sudo: Required for privilege escalation
#   - python3: Required by Ansible
#   - python3-pip: For installing Python packages if needed
#   - ssh-import-id: For importing SSH keys from GitHub/Launchpad
#   - curl, wget: Common utilities
#   - ca-certificates, gnupg: For secure package management
# ==============================================================================

set -euo pipefail

echo "=== Provisioning Ansible-Ready LXC Template ==="

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Ansible prerequisites
echo "Installing Ansible prerequisites..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  sudo \
  python3 \
  python3-pip \
  ssh-import-id \
  curl \
  wget \
  ca-certificates \
  gnupg

# Verify Python is accessible (Ansible requires this)
echo "Verifying Python installation..."
python3 --version

# Clean up package cache to reduce template size
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove SSH host keys (will be regenerated on first boot)
echo "Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Clear machine-id (will be regenerated on first boot)
echo "Clearing machine-id..."
truncate -s 0 /etc/machine-id

# Create marker file for verification
echo "Creating marker file..."
cat > /etc/ansible-ready << EOF
Ansible-ready LXC template built by Packer
Template: debian-12-ansible-ready
Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Packages: sudo python3 python3-pip ssh-import-id curl wget ca-certificates gnupg
EOF

echo "=== Provisioning Complete ==="
