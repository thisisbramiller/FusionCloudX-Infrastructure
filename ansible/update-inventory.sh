#!/bin/bash
# ==============================================================================
# Update Ansible Inventory from Terraform Outputs
# ==============================================================================
# This script extracts PostgreSQL LXC container IPs from Terraform and
# updates the Ansible inventory file
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

# Extract PostgreSQL container information
POSTGRESQL_JSON=$(terraform output -json ansible_inventory_postgresql 2>/dev/null || echo "{}")

if [ "$POSTGRESQL_JSON" = "{}" ]; then
    echo -e "${YELLOW}Warning: No PostgreSQL containers found in Terraform outputs${NC}"
    echo -e "${YELLOW}Make sure you've run 'terraform apply' first${NC}"
    exit 1
fi

# Parse JSON and build inventory entries
echo -e "${BLUE}Parsing container information...${NC}"
POSTGRESQL_ENTRIES=""

while IFS= read -r line; do
    if [ ! -z "$line" ]; then
        POSTGRESQL_ENTRIES="${POSTGRESQL_ENTRIES}${line}\n"
    fi
done < <(echo "$POSTGRESQL_JSON" | jq -r 'to_entries[] | "\(.key) ansible_host=\(.value.ip | gsub("/24$"; ""))"')

# Create temporary inventory file
cp "$INVENTORY_FILE" "$TEMP_INVENTORY"

# Update the [postgresql] section
echo -e "${BLUE}Updating inventory file...${NC}"

# Use awk to replace the [postgresql] section
awk -v entries="$POSTGRESQL_ENTRIES" '
BEGIN { in_postgresql = 0; printed_entries = 0 }
/^\[postgresql\]/ {
    print $0
    in_postgresql = 1
    next
}
/^\[.*\]/ {
    if (in_postgresql == 1 && printed_entries == 0) {
        printf "%b", entries
        printed_entries = 1
    }
    in_postgresql = 0
}
{
    if (in_postgresql == 0) {
        print $0
    } else if ($0 ~ /^[a-zA-Z]/ && $0 !~ /^#/) {
        # Skip old entries in postgresql section
        next
    } else {
        print $0
    }
}
END {
    if (in_postgresql == 1 && printed_entries == 0) {
        printf "%b", entries
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
echo "PostgreSQL containers added:"
echo -e "${POSTGRESQL_ENTRIES}" | sed 's/\\n$//'
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review the updated inventory: cat $INVENTORY_FILE"
echo "2. Test connectivity: ansible postgresql -m ping"
echo "3. Deploy PostgreSQL: ansible-playbook playbooks/postgresql.yml"
echo ""
