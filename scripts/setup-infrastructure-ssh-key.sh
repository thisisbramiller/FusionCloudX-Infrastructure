#!/usr/bin/env bash
# ==============================================================================
# Setup Infrastructure SSH Key in 1Password
# ==============================================================================
# This script creates an ED25519 SSH key in 1Password for infrastructure access
# The key is used by Terraform for provisioning VMs and LXC containers
#
# REQUIREMENTS:
# - 1Password CLI installed (op)
# - 1Password Connect Server environment variables set:
#   - OP_CONNECT_HOST (e.g., http://192.168.40.44:8080)
#   - OP_CONNECT_TOKEN
# - Vault ID from terraform.auto.tfvars
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSH_KEY_TITLE="Infrastructure SSH Key (Terraform)"
VAULT_ID="${TF_VAR_onepassword_vault_id:-}"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}  Infrastructure SSH Key Setup${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

# Check op CLI
if ! command -v op &> /dev/null; then
    echo -e "${RED}✗ 1Password CLI (op) is not installed${NC}"
    echo "  Install from: https://developer.1password.com/docs/cli/get-started/"
    exit 1
fi
echo -e "${GREEN}✓ 1Password CLI installed${NC}"

# Check Connect Server configuration
if [ -z "${OP_CONNECT_HOST:-}" ]; then
    echo -e "${RED}✗ OP_CONNECT_HOST environment variable not set${NC}"
    echo "  Set it to your Connect Server URL (e.g., http://192.168.40.44:8080)"
    exit 1
fi
echo -e "${GREEN}✓ OP_CONNECT_HOST: ${OP_CONNECT_HOST}${NC}"

if [ -z "${OP_CONNECT_TOKEN:-}" ]; then
    echo -e "${RED}✗ OP_CONNECT_TOKEN environment variable not set${NC}"
    exit 1
fi
echo -e "${GREEN}✓ OP_CONNECT_TOKEN is set${NC}"

# Check Vault ID
if [ -z "$VAULT_ID" ]; then
    echo -e "${YELLOW}⚠  TF_VAR_onepassword_vault_id not set${NC}"
    echo -e "${BLUE}Please enter your 1Password vault ID:${NC}"
    read -r VAULT_ID
fi
echo -e "${GREEN}✓ Vault ID: ${VAULT_ID}${NC}"

echo ""

# Check if SSH key already exists
echo -e "${BLUE}Checking for existing SSH key...${NC}"
if op item get "$SSH_KEY_TITLE" --vault "$VAULT_ID" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠  SSH key '$SSH_KEY_TITLE' already exists in 1Password${NC}"
    echo -e "${BLUE}Do you want to recreate it? (y/N):${NC} "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✓ Using existing SSH key${NC}"

        # Display public key
        echo ""
        echo -e "${BLUE}Public key:${NC}"
        op item get "$SSH_KEY_TITLE" --vault "$VAULT_ID" --fields label="public key"
        echo ""
        echo -e "${GREEN}✓ Setup complete!${NC}"
        exit 0
    fi

    # Delete existing key
    echo -e "${YELLOW}Deleting existing SSH key...${NC}"
    op item delete "$SSH_KEY_TITLE" --vault "$VAULT_ID"
    echo -e "${GREEN}✓ Deleted${NC}"
fi

# Create new SSH key
echo -e "${BLUE}Creating new ED25519 SSH key in 1Password...${NC}"
op item create \
    --category "SSH Key" \
    --title "$SSH_KEY_TITLE" \
    --vault "$VAULT_ID" \
    --generate-password=off \
    --ssh-generate-key \
    --tags terraform,ssh,infrastructure,homelab

# Add notes
op item edit "$SSH_KEY_TITLE" \
    --vault "$VAULT_ID" \
    notes="Infrastructure SSH key for homelab VMs, LXC containers, and Proxmox host. Generated for Terraform provisioning. Works with 1Password SSH agent."

echo -e "${GREEN}✓ SSH key created successfully!${NC}"
echo ""

# Display public key
echo -e "${BLUE}Public key:${NC}"
PUBLIC_KEY=$(op item get "$SSH_KEY_TITLE" --vault "$VAULT_ID" --fields label="public key")
echo "$PUBLIC_KEY"
echo ""

# Display fingerprint
echo -e "${BLUE}Fingerprint:${NC}"
op item get "$SSH_KEY_TITLE" --vault "$VAULT_ID" --fields label=fingerprint
echo ""

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Run 'terraform init' to initialize Terraform"
echo "  2. Run 'terraform plan' to see what will be created"
echo "  3. Run 'terraform apply' to provision infrastructure"
echo ""
echo -e "${BLUE}Note:${NC} The private key is securely stored in 1Password"
echo "      and will be accessible via 1Password SSH agent"
echo ""
