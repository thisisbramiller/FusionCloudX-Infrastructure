#!/bin/bash
# ==============================================================================
# Setup Ansible Vault
# ==============================================================================
# This script helps you set up ansible-vault for secure password management
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_PASS_FILE="$SCRIPT_DIR/.vault_pass"
VAULT_FILE="$SCRIPT_DIR/inventory/group_vars/vault.yml"

echo -e "${BLUE}========================================"
echo "Ansible Vault Setup"
echo -e "========================================${NC}"

# Step 1: Create vault password file
if [ -f "$VAULT_PASS_FILE" ]; then
    echo -e "${YELLOW}Vault password file already exists at $VAULT_PASS_FILE${NC}"
    read -p "Do you want to generate a new password? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Keeping existing vault password${NC}"
    else
        # Generate new password
        echo -e "${BLUE}Generating new vault password...${NC}"
        openssl rand -base64 32 > "$VAULT_PASS_FILE"
        chmod 600 "$VAULT_PASS_FILE"
        echo -e "${GREEN}New vault password generated and saved${NC}"
    fi
else
    echo -e "${BLUE}Creating vault password file...${NC}"
    openssl rand -base64 32 > "$VAULT_PASS_FILE"
    chmod 600 "$VAULT_PASS_FILE"
    echo -e "${GREEN}Vault password file created at $VAULT_PASS_FILE${NC}"
fi

echo ""
echo -e "${YELLOW}IMPORTANT: Back up your vault password! You'll need it to decrypt secrets.${NC}"
echo "Vault password: $(cat $VAULT_PASS_FILE)"
echo ""

# Step 2: Encrypt vault.yml if not already encrypted
if [ -f "$VAULT_FILE" ]; then
    # Check if already encrypted
    if head -n 1 "$VAULT_FILE" | grep -q '$ANSIBLE_VAULT'; then
        echo -e "${GREEN}vault.yml is already encrypted${NC}"
    else
        echo -e "${YELLOW}vault.yml is not encrypted. Encrypting now...${NC}"
        ansible-vault encrypt "$VAULT_FILE"
        echo -e "${GREEN}vault.yml encrypted successfully${NC}"
    fi
else
    echo -e "${RED}Error: vault.yml not found at $VAULT_FILE${NC}"
    exit 1
fi

# Step 3: Verify vault setup
echo ""
echo -e "${BLUE}Verifying vault setup...${NC}"

# Test decryption
if ansible-vault view "$VAULT_FILE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Vault password file is working${NC}"
    echo -e "${GREEN}✓ Can decrypt vault.yml${NC}"
else
    echo -e "${RED}✗ Failed to decrypt vault.yml${NC}"
    echo -e "${RED}Check your vault password file${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================"
echo "Vault setup complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Edit encrypted passwords: ansible-vault edit inventory/group_vars/vault.yml"
echo "2. View encrypted file: ansible-vault view inventory/group_vars/vault.yml"
echo "3. Change vault password: ansible-vault rekey inventory/group_vars/vault.yml"
echo ""
echo -e "${YELLOW}Remember:${NC}"
echo "- Never commit .vault_pass to git (already in .gitignore)"
echo "- Back up your vault password securely"
echo "- Vault password is required to run playbooks"
echo ""
