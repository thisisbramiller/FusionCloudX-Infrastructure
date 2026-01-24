#!/bin/bash
# ==============================================================================
# 1Password Connect Test Script
# ==============================================================================
# This script tests the 1Password Connect collection setup
# Run this after setting up authentication to verify everything works
# ==============================================================================

set -e  # Exit on error

echo "========================================"
echo "1Password Connect Test Script"
echo "========================================"
echo ""

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Check if ansible is installed
echo "Test 1: Checking Ansible installation..."
if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(ansible --version | head -n1)
    echo -e "${GREEN}✓${NC} Ansible installed: $ANSIBLE_VERSION"
else
    echo -e "${RED}✗${NC} Ansible not found. Please install Ansible first."
    exit 1
fi
echo ""

# Test 2: Check environment variables
echo "Test 2: Checking 1Password authentication..."
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo -e "${GREEN}✓${NC} OP_SERVICE_ACCOUNT_TOKEN is set (Service Account method)"
    AUTH_METHOD="service_account"
elif [ -n "$OP_CONNECT_HOST" ] && [ -n "$OP_CONNECT_TOKEN" ]; then
    echo -e "${GREEN}✓${NC} OP_CONNECT_HOST and OP_CONNECT_TOKEN are set (Connect Server method)"
    echo "   Connect Host: $OP_CONNECT_HOST"
    AUTH_METHOD="connect_server"
else
    echo -e "${RED}✗${NC} No 1Password authentication found!"
    echo "   Please set either:"
    echo "   - OP_SERVICE_ACCOUNT_TOKEN (for Service Account)"
    echo "   - OP_CONNECT_HOST and OP_CONNECT_TOKEN (for Connect Server)"
    exit 1
fi
echo ""

# Test 3: Check if collection requirements.yml exists
echo "Test 3: Checking requirements.yml..."
if [ -f "requirements.yml" ]; then
    echo -e "${GREEN}✓${NC} requirements.yml found"
else
    echo -e "${RED}✗${NC} requirements.yml not found"
    exit 1
fi
echo ""

# Test 4: Install/verify collection
echo "Test 4: Installing 1Password Connect collection..."
if ansible-galaxy collection install -r requirements.yml > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Collection installed successfully"
else
    echo -e "${YELLOW}!${NC} Collection installation had warnings (may already be installed)"
fi
echo ""

# Test 5: Verify collection is installed
echo "Test 5: Verifying collection installation..."
if ansible-galaxy collection list | grep -q "onepassword.connect"; then
    COLLECTION_VERSION=$(ansible-galaxy collection list | grep "onepassword.connect" | awk '{print $2}')
    echo -e "${GREEN}✓${NC} onepassword.connect collection found (version: $COLLECTION_VERSION)"
else
    echo -e "${RED}✗${NC} onepassword.connect collection not found"
    exit 1
fi
echo ""

# Test 6: Test Connect Server health (if using Connect Server)
if [ "$AUTH_METHOD" = "connect_server" ]; then
    echo "Test 6: Testing Connect Server connectivity..."
    if command -v curl &> /dev/null; then
        HEALTH_CHECK=$(curl -s -H "Authorization: Bearer $OP_CONNECT_TOKEN" "$OP_CONNECT_HOST/health" 2>&1)
        if echo "$HEALTH_CHECK" | grep -q "1Password Connect"; then
            echo -e "${GREEN}✓${NC} Connect Server is reachable and healthy"
        else
            echo -e "${RED}✗${NC} Connect Server health check failed"
            echo "   Response: $HEALTH_CHECK"
            exit 1
        fi
    else
        echo -e "${YELLOW}!${NC} curl not found, skipping Connect Server health check"
    fi
    echo ""
fi

# Test 7: Test lookup with Ansible
echo "Test 7: Testing 1Password lookup..."
echo "   Attempting to retrieve: PostgreSQL Admin (postgres)"
echo "   Vault: FusionCloudX Infrastructure"

LOOKUP_CMD="ansible localhost -m debug -a \"msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}\""

if eval "$LOOKUP_CMD" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Successfully retrieved credential from 1Password"
else
    echo -e "${RED}✗${NC} Failed to retrieve credential from 1Password"
    echo "   This could mean:"
    echo "   - Item 'PostgreSQL Admin (postgres)' doesn't exist in vault"
    echo "   - Vault 'FusionCloudX Infrastructure' doesn't exist"
    echo "   - Service Account doesn't have access to the vault"
    echo "   - Authentication credentials are invalid"
    echo ""
    echo "   Run with verbose output to debug:"
    echo "   $LOOKUP_CMD -vvv"
    exit 1
fi
echo ""

# Test 8: Check inventory file
echo "Test 8: Checking inventory configuration..."
if [ -f "inventory/hosts.ini" ]; then
    echo -e "${GREEN}✓${NC} inventory/hosts.ini found"
else
    echo -e "${YELLOW}!${NC} inventory/hosts.ini not found (may need to run update-inventory.sh)"
fi
echo ""

# Test 9: Check host_vars
echo "Test 9: Checking host_vars configuration..."
if [ -f "inventory/host_vars/postgresql.yml" ]; then
    echo -e "${GREEN}✓${NC} inventory/host_vars/postgresql.yml found"

    # Check if it's using the new syntax
    if grep -q "onepassword.connect.generic_item" "inventory/host_vars/postgresql.yml"; then
        echo -e "${GREEN}✓${NC} Using official 1Password Connect collection syntax"
    else
        echo -e "${YELLOW}!${NC} Not using official collection syntax (may need update)"
    fi
else
    echo -e "${YELLOW}!${NC} inventory/host_vars/postgresql.yml not found"
fi
echo ""

# Test 10: Syntax check playbook
echo "Test 10: Checking playbook syntax..."
if [ -f "playbooks/postgresql.yml" ]; then
    if ansible-playbook playbooks/postgresql.yml --syntax-check > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} playbooks/postgresql.yml syntax is valid"
    else
        echo -e "${RED}✗${NC} playbooks/postgresql.yml has syntax errors"
        exit 1
    fi
else
    echo -e "${YELLOW}!${NC} playbooks/postgresql.yml not found"
fi
echo ""

# Final summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}All tests passed!${NC}"
echo ""
echo "Next steps:"
echo "1. Test connectivity: ansible postgresql -m ping"
echo "2. Run playbook (check mode): ansible-playbook playbooks/postgresql.yml --check"
echo "3. Run playbook: ansible-playbook playbooks/postgresql.yml"
echo ""
echo "Authentication method: $AUTH_METHOD"
echo "Collection version: $COLLECTION_VERSION"
echo ""
echo "For troubleshooting, see:"
echo "- 1PASSWORD_MIGRATION.md"
echo "- ONEPASSWORD_QUICKSTART.md"
echo "- README.md"
echo "========================================"
