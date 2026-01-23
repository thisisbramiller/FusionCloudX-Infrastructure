#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Semaphore Control Plane
# ==============================================================================
# This script helps you bootstrap the semaphore-ui VM as the control plane
#
# PREREQUISITES:
#   1. semaphore-ui VM is provisioned and running
#   2. You can SSH to semaphore-ui as 'ansible' user
#   3. PostgreSQL database is running
#   4. You have a 1Password service account token
#
# USAGE:
#   ./scripts/bootstrap-control-plane.sh
# ==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo "  $1"
}

# ==============================================================================
# Pre-flight Checks
# ==============================================================================

print_header "SEMAPHORE CONTROL PLANE BOOTSTRAP"

echo "This script will configure semaphore-ui as your Infrastructure Control Plane."
echo "It will install Terraform, 1Password CLI, Semaphore UI, and configure SSH keys."
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Check if Ansible is installed
print_info "Checking prerequisites..."
if ! command -v ansible &> /dev/null; then
    print_error "Ansible is not installed on your workstation"
    echo "Install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/index.html"
    exit 1
fi
print_success "Ansible is installed"

# Check if we're in the right directory
if [ ! -f "$ANSIBLE_DIR/playbooks/bootstrap-semaphore.yml" ]; then
    print_error "Cannot find bootstrap playbook. Are you in the right directory?"
    exit 1
fi
print_success "Found bootstrap playbook"

# ==============================================================================
# Get Configuration from User
# ==============================================================================

print_header "CONFIGURATION"

# Get Semaphore IP
echo "Enter the IP address of your semaphore-ui VM:"
read -p "IP Address: " SEMAPHORE_IP
if [ -z "$SEMAPHORE_IP" ]; then
    print_error "IP address is required"
    exit 1
fi

# Test SSH connectivity
print_info "Testing SSH connection to $SEMAPHORE_IP..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ansible@$SEMAPHORE_IP "exit" 2>/dev/null; then
    print_success "SSH connection successful"
else
    print_error "Cannot SSH to ansible@$SEMAPHORE_IP"
    echo "Make sure:"
    echo "  1. The VM is running"
    echo "  2. You can SSH as 'ansible' user"
    echo "  3. Your SSH key is in ansible user's authorized_keys"
    exit 1
fi

# Get 1Password token
echo ""
echo "Enter your 1Password service account token:"
read -sp "Token: " ONEPASSWORD_TOKEN
echo ""
if [ -z "$ONEPASSWORD_TOKEN" ]; then
    print_warning "No 1Password token provided"
    echo "You can configure this later in Semaphore"
fi

# Get database password (optional)
echo ""
echo "Enter PostgreSQL semaphore user password (or leave blank to configure later):"
read -sp "Password: " DB_PASSWORD
echo ""

# ==============================================================================
# Update Bootstrap Inventory
# ==============================================================================

print_header "UPDATING INVENTORY"

BOOTSTRAP_INVENTORY="$ANSIBLE_DIR/inventory/bootstrap-semaphore.ini"
print_info "Updating $BOOTSTRAP_INVENTORY with IP: $SEMAPHORE_IP"

# Update the inventory file
sed -i "s/ansible_host=192.168.1.XXX/ansible_host=$SEMAPHORE_IP/" "$BOOTSTRAP_INVENTORY"
print_success "Inventory updated"

# ==============================================================================
# Run Bootstrap Playbook
# ==============================================================================

print_header "RUNNING BOOTSTRAP PLAYBOOK"

cd "$ANSIBLE_DIR"

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook -i inventory/bootstrap-semaphore.ini playbooks/bootstrap-semaphore.yml"

# Add 1Password token if provided
if [ ! -z "$ONEPASSWORD_TOKEN" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e \"onepassword_service_account_token=$ONEPASSWORD_TOKEN\""
fi

# Add database password if provided
if [ ! -z "$DB_PASSWORD" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e \"semaphore_db_password=$DB_PASSWORD\""
fi

print_info "Running: $ANSIBLE_CMD"
echo ""

# Execute the playbook
eval $ANSIBLE_CMD

# ==============================================================================
# Post-Bootstrap Instructions
# ==============================================================================

if [ $? -eq 0 ]; then
    print_header "BOOTSTRAP SUCCESSFUL!"

    print_success "Semaphore Control Plane is configured"
    echo ""
    echo "Access Semaphore UI: http://$SEMAPHORE_IP:3000"
    echo ""

    print_header "NEXT STEPS"

    echo "1. CONFIGURE GITHUB DEPLOY KEY:"
    print_info "SSH to semaphore-ui and get the public key:"
    print_info "  ssh ansible@$SEMAPHORE_IP 'cat ~/.ssh/github_deploy_key.pub'"
    print_info "Add this key to GitHub: Repository Settings → Deploy keys"
    echo ""

    echo "2. CONFIGURE PROXMOX SSH ACCESS:"
    print_info "Get the Proxmox public key:"
    print_info "  ssh ansible@$SEMAPHORE_IP 'cat ~/.ssh/proxmox_terraform_key.pub'"
    print_info "Add to Proxmox terraform user's authorized_keys"
    echo ""

    echo "3. COMPLETE SEMAPHORE INITIAL SETUP:"
    print_info "Open http://$SEMAPHORE_IP:3000"
    print_info "Create the first admin user"
    echo ""

    echo "4. ADD REPOSITORY TO SEMAPHORE:"
    print_info "Configure the infrastructure repository"
    print_info "Create task templates for Ansible and Terraform"
    echo ""

    echo "5. TEST YOUR SETUP:"
    print_info "Run a simple playbook from Semaphore"
    print_info "Verify everything works"
    echo ""

    print_success "You're all set! Manage infrastructure through Semaphore UI now."
else
    print_header "BOOTSTRAP FAILED"
    print_error "Something went wrong during bootstrap"
    echo "Check the Ansible output above for details"
    exit 1
fi
