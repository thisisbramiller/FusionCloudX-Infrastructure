#!/usr/bin/env zsh
# ==============================================================================
# Update Ansible Inventory from Terraform Outputs
# ==============================================================================
# This script extracts VM IPs from Terraform and updates the Ansible inventory
# Handles multiple VMs: semaphore-ui, gitlab, postgresql
# Compatible with bash and zsh on macOS and Linux
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths - compatible with both bash and zsh
if [[ -n "${ZSH_VERSION:-}" ]]; then
    # zsh
    SCRIPT_DIR="${0:a:h}"
else
    # bash
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
INVENTORY_FILE="$SCRIPT_DIR/inventory/hosts.ini"
TEMP_INVENTORY="/tmp/hosts.ini.tmp.$$"

echo -e "${BLUE}========================================"
echo "Updating Ansible Inventory from Terraform"
echo "========================================"
echo "Discovering: semaphore-ui, gitlab, postgresql"
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

# Extract VM and container information
SEMAPHORE_JSON=$(terraform output -json ansible_inventory_semaphore 2>/dev/null || echo "{}")
GITLAB_JSON=$(terraform output -json ansible_inventory_gitlab 2>/dev/null || echo "{}")
POSTGRESQL_JSON=$(terraform output -json ansible_inventory_postgresql 2>/dev/null || echo "{}")

# Initialize variables
SEMAPHORE_ENTRY=""
GITLAB_ENTRY=""
POSTGRESQL_ENTRY=""
DATABASES=""

# Parse Semaphore UI
if [ "$SEMAPHORE_JSON" != "{}" ] && [ "$SEMAPHORE_JSON" != "null" ]; then
    SEMAPHORE_HOSTNAME=$(echo "$SEMAPHORE_JSON" | jq -r '.hostname')
    SEMAPHORE_IP=$(echo "$SEMAPHORE_JSON" | jq -r '.ip' | sed 's|/24$||')
    SEMAPHORE_ENTRY="$SEMAPHORE_HOSTNAME ansible_host=$SEMAPHORE_IP"
    echo -e "${GREEN}Found Semaphore UI:${NC}"
    echo "  Hostname: $SEMAPHORE_HOSTNAME"
    echo "  IP: $SEMAPHORE_IP"
else
    echo -e "${YELLOW}Warning: Semaphore UI not found in Terraform outputs${NC}"
fi

# Parse GitLab
if [ "$GITLAB_JSON" != "{}" ] && [ "$GITLAB_JSON" != "null" ]; then
    GITLAB_HOSTNAME=$(echo "$GITLAB_JSON" | jq -r '.hostname')
    GITLAB_IP=$(echo "$GITLAB_JSON" | jq -r '.ip' | sed 's|/24$||')
    GITLAB_ENTRY="$GITLAB_HOSTNAME ansible_host=$GITLAB_IP"
    echo -e "${GREEN}Found GitLab:${NC}"
    echo "  Hostname: $GITLAB_HOSTNAME"
    echo "  IP: $GITLAB_IP"
else
    echo -e "${YELLOW}Warning: GitLab not found in Terraform outputs${NC}"
fi

# Parse PostgreSQL
if [ "$POSTGRESQL_JSON" != "{}" ] && [ "$POSTGRESQL_JSON" != "null" ]; then
    POSTGRESQL_HOSTNAME=$(echo "$POSTGRESQL_JSON" | jq -r '.hostname')
    POSTGRESQL_IP=$(echo "$POSTGRESQL_JSON" | jq -r '.ip' | sed 's|/24$||')
    POSTGRESQL_ENTRY="$POSTGRESQL_HOSTNAME ansible_host=$POSTGRESQL_IP"
    DATABASES=$(echo "$POSTGRESQL_JSON" | jq -r '.databases[].name' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo -e "${GREEN}Found PostgreSQL:${NC}"
    echo "  Hostname: $POSTGRESQL_HOSTNAME"
    echo "  IP: $POSTGRESQL_IP"
    echo "  Databases: $DATABASES"
else
    echo -e "${YELLOW}Warning: PostgreSQL not found in Terraform outputs${NC}"
    exit 1
fi

# Create temporary inventory file
cp "$INVENTORY_FILE" "$TEMP_INVENTORY"

echo -e "${BLUE}Updating inventory file...${NC}"

# Update the inventory with all VMs using Python for better portability
python3 << PYSCRIPT
import sys
import re

inventory_file = "$INVENTORY_FILE"
temp_inventory = "$TEMP_INVENTORY"

# Read the inventory file
with open(inventory_file, 'r') as f:
    lines = f.readlines()

# Prepare replacement entries
entries = {
    'semaphore': "$SEMAPHORE_ENTRY",
    'gitlab': "$GITLAB_ENTRY",
    'postgresql': "$POSTGRESQL_ENTRY"
}

# Process the file
output = []
i = 0

while i < len(lines):
    line = lines[i]
    
    # Check if this is a section header
    if line.startswith('[') and line.rstrip().endswith(']'):
        # Extract section name (before any :)
        match = re.match(r'\[([a-zA-Z_]+)', line)
        if match:
            section_name = match.group(1)
            output.append(line)
            
            # If this is a section we need to update
            if section_name in entries and entries[section_name]:
                # Skip old entries until next section or vars line
                i += 1
                entry_added = False
                
                while i < len(lines):
                    next_line = lines[i]
                    
                    # Stop if we hit another section
                    if next_line.startswith('['):
                        i -= 1  # Back up one line
                        break
                    
                    # Keep comments, blank lines, and vars lines
                    if next_line.startswith('#') or next_line.strip() == '' or next_line.startswith('ansible_'):
                        output.append(next_line)
                        i += 1
                    else:
                        # Skip old host entries
                        i += 1
                
                # Add the new entry if we haven't already
                if entries[section_name] and not entry_added:
                    output.append(entries[section_name] + '\n')
        else:
            output.append(line)
    else:
        output.append(line)
    
    i += 1

# Write the updated inventory
with open(temp_inventory, 'w') as f:
    f.writelines(output)
PYSCRIPT

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
if [ -n "$SEMAPHORE_ENTRY" ]; then
    echo "Semaphore UI added: $SEMAPHORE_ENTRY"
fi
if [ -n "$GITLAB_ENTRY" ]; then
    echo "GitLab added: $GITLAB_ENTRY"
fi
if [ -n "$POSTGRESQL_ENTRY" ]; then
    echo "PostgreSQL added: $POSTGRESQL_ENTRY"
    [ -n "$DATABASES" ] && echo "  (Databases: $DATABASES)"
fi
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review the updated inventory: cat $INVENTORY_FILE"
echo "2. Test connectivity:"
if [ -n "$SEMAPHORE_ENTRY" ]; then
    echo "   - ansible semaphore -m ping"
fi
if [ -n "$GITLAB_ENTRY" ]; then
    echo "   - ansible gitlab -m ping"
fi
if [ -n "$POSTGRESQL_ENTRY" ]; then
    echo "   - ansible postgresql -m ping"
fi
echo "3. Deploy services: ansible-playbook playbooks/site.yml"
echo ""
