#!/bin/bash
# ==============================================================================
# Update Ansible Inventory from Terraform Outputs
# ==============================================================================
# This script extracts the PostgreSQL LXC container IP from Terraform and
# updates the Ansible inventory file
# Note: Single PostgreSQL container hosting multiple databases
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
INVENTORY_FILE="$SCRIPT_DIR/inventory/hosts.ini"
TEMP_INVENTORY="/tmp/hosts.ini.tmp"

echo -e "${BLUE}========================================"
echo "Updating Ansible Inventory from Terraform"
echo "========================================"
echo "Single PostgreSQL container architecture"
echo -e "========================================${NC}"

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${RED}Error: Terraform directory not found at $TERRAFORM_DIR${NC}"
    exit 1
fi

# Change to terraform directory
cd "$TERRAFORM_DIR"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Terraform not initialized. Running terraform init...${NC}"
    terraform init
fi

# Get Terraform outputs
echo -e "${BLUE}Fetching Terraform outputs...${NC}"

# Extract PostgreSQL container information (single container)
POSTGRESQL_JSON=$(terraform output -json ansible_inventory_postgresql 2>/dev/null || echo "{}")

if [ "$POSTGRESQL_JSON" = "{}" ] || [ "$POSTGRESQL_JSON" = "null" ]; then
    echo -e "${YELLOW}Warning: PostgreSQL container not found in Terraform outputs${NC}"
    echo -e "${YELLOW}Make sure you've run 'terraform apply' first${NC}"
    exit 1
fi

# Parse JSON and extract container details
echo -e "${BLUE}Parsing container information...${NC}"
HOSTNAME=$(echo "$POSTGRESQL_JSON" | jq -r '.hostname')
IP=$(echo "$POSTGRESQL_JSON" | jq -r '.ip' | sed 's|/24$||')
VM_ID=$(echo "$POSTGRESQL_JSON" | jq -r '.vm_id')
DATABASES=$(echo "$POSTGRESQL_JSON" | jq -r '.databases[].name' | tr '\n' ',' | sed 's/,$//')

echo -e "${GREEN}Found PostgreSQL container:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP"
echo "  VM ID: $VM_ID"
echo "  Databases: $DATABASES"

# Create inventory entry
POSTGRESQL_ENTRY="$HOSTNAME ansible_host=$IP"

# Create temporary inventory file
cp "$INVENTORY_FILE" "$TEMP_INVENTORY"

# Update the [postgresql] section
echo -e "${BLUE}Updating inventory file...${NC}"

# Use awk to replace the [postgresql] section
awk -v entry="$POSTGRESQL_ENTRY" '
BEGIN { in_postgresql = 0; printed_entry = 0 }
/^\[postgresql\]/ {
    print $0
    in_postgresql = 1
    next
}
/^\[.*\]/ {
    if (in_postgresql == 1 && printed_entry == 0) {
        print entry
        printed_entry = 1
    }
    in_postgresql = 0
}
{
    if (in_postgresql == 0) {
        print $0
    } else if ($0 ~ /^#/ || $0 ~ /^$/) {
        # Keep comments and blank lines in postgresql section
        print $0
    } else if ($0 ~ /^[a-zA-Z]/ && $0 !~ /^ansible_/) {
        # Skip old host entries (but keep ansible_ variables)
        next
    } else {
        print $0
    }
}
END {
    if (in_postgresql == 1 && printed_entry == 0) {
        print entry
    }
}
' "$INVENTORY_FILE" > "$TEMP_INVENTORY"

# Backup original inventory
BACKUP_FILE="$INVENTORY_FILE.backup.$(date +%Y%m%d_%H%M%S)"
cp "$INVENTORY_FILE" "$BACKUP_FILE"
echo -e "${GREEN}Created backup: $BACKUP_FILE${NC}"

# Replace original with updated version
mv "$TEMP_INVENTORY" "$INVENTORY_FILE"

echo -e "${GREEN}========================================"
echo "Inventory update complete!"
echo -e "========================================${NC}"
echo ""
echo "PostgreSQL container added:"
echo "  $POSTGRESQL_ENTRY"
echo "  (Hosting databases: $DATABASES)"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review the updated inventory: cat $INVENTORY_FILE"
echo "2. Test connectivity: ansible postgresql -m ping"
echo "3. Deploy PostgreSQL: ansible-playbook playbooks/postgresql.yml"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "- This is a SINGLE container hosting MULTIPLE databases"
echo "- Ensure 1Password CLI is installed and authenticated"
echo "- Database credentials are managed via 1Password"
echo ""
