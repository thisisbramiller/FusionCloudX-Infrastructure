# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing Proxmox Virtual Environment (PVE) resources using Terraform and Ansible. The repository provisions Ubuntu VMs from cloud images and configures them with Ansible.

## Architecture

### Terraform Structure

The Terraform configuration is split into logical files:

- `provider.tf` - Proxmox provider configuration using the `bpg/proxmox` provider (v0.88.0). Authentication uses SSH agent with user `terraform`. The provider connects to node `zero.fusioncloudx.home:8006`
- `backend.tf` - Local state backend (stores state in `terraform.tfstate` at project root)
- `ubuntu-template.tf` - Creates a VM template (ID 1000) from Ubuntu Noble cloud image. This downloads the image to `nas-infrastructure` datastore and creates a template with SCSI disk on `vm-data`
- `cloud-init.tf` - Defines cloud-init user data configuration stored as a snippet on `nas-infrastructure` datastore
- `main.tf` - Creates VM instances by cloning the template. VMs depend on the template being created first
- `outputs.tf` - Exports VM IPv4 address from the QEMU guest agent (index [1][0])
- `variables.tf` - Currently minimal/empty but exists for future variable definitions

### Key Terraform Resources

**Template Creation Flow:**
1. `proxmox_virtual_environment_download_file.ubuntu-cloud-image` downloads Ubuntu Noble cloud image
2. `proxmox_virtual_environment_vm.ubuntu-template` creates template (VM ID 1000) from the downloaded image
3. Template is marked with `template = true` and `started = false`

**VM Provisioning Flow:**
1. `proxmox_virtual_environment_file.user_data_cloud_config` creates cloud-init configuration
2. `proxmox_virtual_environment_vm.test_vm` clones template 1000 with full clone
3. Cloud-init runs with custom user data (creates `fcx` user, installs packages, enables qemu-guest-agent)

### Cloud-Init Configuration

The cloud-init config in `cloud-init.tf`:
- Sets hostname to "test" and timezone to America/Chicago
- Creates user `fcx` with sudo access (NOPASSWD) and SSH key import from GitHub user `thisisbramiller`
- Password authentication disabled (`lock_passwd: true`)
- Installs: qemu-guest-agent, net-tools, curl
- Enables and starts qemu-guest-agent service

### Ansible Structure

- `ansible.cfg` - Points to `./inventory/hosts.ini`, disables host key checking and retry files
- `inventory/hosts.ini` - Currently configured for localhost only with commented examples for remote hosts
- `group_vars/all.yml` - Global variables (currently minimal)
- `playbooks/site.yml` - Main playbook applying the `common` role to all hosts
- `roles/common/` - Basic role that updates apt, installs nginx, creates fusionuser, and ensures nginx is running

## Common Commands

### Terraform

Work from the `terraform/` directory:

```bash
# Initialize Terraform and download providers
terraform init

# Plan infrastructure changes
terraform plan

# Apply infrastructure changes
terraform apply

# Show current state
terraform show

# Get outputs (e.g., VM IP address)
terraform output

# Destroy infrastructure
terraform destroy
```

### Ansible

Work from the `ansible/` directory:

```bash
# Run the main site playbook
ansible-playbook playbooks/site.yml

# Run playbook with specific inventory
ansible-playbook -i inventory/hosts.ini playbooks/site.yml

# Check connectivity
ansible all -m ping

# Run ad-hoc commands
ansible all -m shell -a "uptime"
```

## Important Notes

### Proxmox Authentication
- The Terraform provider uses SSH agent authentication with the `terraform` user
- Ensure SSH agent is running and has the appropriate key loaded before running Terraform commands
- API endpoint uses self-signed certificates (`insecure = true`)

### Resource Dependencies
- VMs in `main.tf` depend on the template in `ubuntu-template.tf` via `depends_on`
- The template must exist before cloning VMs from it
- Cloud-init file must be created before VM initialization references it

### Datastores
- `nas-infrastructure` - Used for cloud images and cloud-init snippets
- `vm-data` - Used for VM disks and cloud-init configs during initialization

### VM Specifications
- Template: VM ID 1000, named "ubuntu-template", on node "zero"
- VMs are full clones (not linked clones) of the template
- Default VM config: 4 cores (x86-64-v2-AES), 2GB RAM, DHCP networking
- Serial console enabled for all VMs

### State Management
- Terraform state is stored locally in the project root as `terraform.tfstate`
- The state file is excluded from git via `.gitignore`
- Be cautious when working in teams - local state doesn't support locking or collaboration

## Development Workflow

1. Modify Terraform configurations in `terraform/` directory
2. Run `terraform plan` to preview changes
3. Run `terraform apply` to provision infrastructure
4. Use Terraform outputs to get VM IP addresses
5. Update Ansible inventory with provisioned VM IPs
6. Run Ansible playbooks from `ansible/` directory to configure VMs

## Current Branch

The working branch is `vm-clone`. The main branch for PRs is `main`.
