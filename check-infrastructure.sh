#!/bin/bash
# ==============================================================================
# FusionCloudX Infrastructure - Status Check
# ==============================================================================
# This script provides a quick overview of your infrastructure status
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "========================================"
echo "  FusionCloudX Infrastructure Status"
echo "========================================"
echo -e "${NC}"

# Check Terraform
echo -e "${BLUE}[1/4] Checking Terraform...${NC}"
if [ -d "terraform/.terraform" ]; then
    echo -e "${GREEN}✓ Terraform initialized${NC}"

    cd terraform
    if [ -f "terraform.tfstate" ]; then
        echo -e "${GREEN}✓ Terraform state exists${NC}"

        # Count resources
        RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l || echo "0")
        echo -e "${CYAN}  Resources managed: $RESOURCE_COUNT${NC}"

        # Show PostgreSQL containers
        echo -e "${CYAN}  PostgreSQL containers:${NC}"
        terraform state list 2>/dev/null | grep "proxmox_virtual_environment_container.postgresql" || echo -e "${YELLOW}    None deployed yet${NC}"
    else
        echo -e "${YELLOW}⚠ No Terraform state - infrastructure not deployed yet${NC}"
    fi
    cd ..
else
    echo -e "${YELLOW}⚠ Terraform not initialized - run 'terraform init' first${NC}"
fi

echo ""

# Check Ansible
echo -e "${BLUE}[2/4] Checking Ansible...${NC}"
if [ -d "ansible" ]; then
    echo -e "${GREEN}✓ Ansible directory exists${NC}"

    # Check vault password
    if [ -f "ansible/.vault_pass" ]; then
        echo -e "${GREEN}✓ Vault password file exists${NC}"
    else
        echo -e "${YELLOW}⚠ Vault password not set - run 'ansible/setup-vault.sh'${NC}"
    fi

    # Check vault encryption
    if [ -f "ansible/inventory/group_vars/vault.yml" ]; then
        if head -n 1 "ansible/inventory/group_vars/vault.yml" | grep -q '$ANSIBLE_VAULT'; then
            echo -e "${GREEN}✓ Vault file is encrypted${NC}"
        else
            echo -e "${RED}✗ Vault file is NOT encrypted - run 'ansible-vault encrypt ansible/inventory/group_vars/vault.yml'${NC}"
        fi
    fi

    # Check inventory
    if [ -f "ansible/inventory/hosts.ini" ]; then
        POSTGRESQL_COUNT=$(grep -c "postgresql-" "ansible/inventory/hosts.ini" | grep -v "#" || echo "0")
        echo -e "${CYAN}  PostgreSQL hosts in inventory: $POSTGRESQL_COUNT${NC}"
    fi
else
    echo -e "${RED}✗ Ansible directory not found${NC}"
fi

echo ""

# Check connectivity
echo -e "${BLUE}[3/4] Checking connectivity...${NC}"
if command -v ansible &> /dev/null; then
    if [ -f "ansible/inventory/hosts.ini" ]; then
        cd ansible
        echo -e "${CYAN}  Testing PostgreSQL hosts:${NC}"
        ansible postgresql -m ping --one-line 2>/dev/null || echo -e "${YELLOW}    No hosts reachable (not deployed yet or SSH issues)${NC}"
        cd ..
    else
        echo -e "${YELLOW}⚠ No inventory file${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Ansible not installed${NC}"
fi

echo ""

# Show next steps
echo -e "${BLUE}[4/4] Recommended next steps:${NC}"

if [ ! -d "terraform/.terraform" ]; then
    echo -e "${YELLOW}  → Run: cd terraform && terraform init${NC}"
elif [ ! -f "terraform/terraform.tfstate" ]; then
    echo -e "${YELLOW}  → Run: cd terraform && terraform apply${NC}"
elif [ ! -f "ansible/.vault_pass" ]; then
    echo -e "${YELLOW}  → Run: cd ansible && ./setup-vault.sh${NC}"
else
    echo -e "${GREEN}  ✓ Infrastructure looks good!${NC}"
    echo -e "${CYAN}  → Deploy PostgreSQL: cd ansible && ansible-playbook playbooks/postgresql.yml${NC}"
fi

echo ""
echo -e "${CYAN}========================================"
echo "For detailed documentation, see:"
echo "  - DEPLOYMENT-SUMMARY.md"
echo "  - POSTGRESQL-LXC-WORKFLOW.md"
echo "  - QUICK-REFERENCE.md"
echo -e "========================================${NC}"
echo ""
