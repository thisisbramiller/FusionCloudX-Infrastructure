# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing **homelab/development** infrastructure on Proxmox Virtual Environment (PVE) using Terraform and Ansible. This repository provisions Ubuntu VMs for testing and development purposes. **Production workloads will be deployed separately on AWS infrastructure.**

## Architecture

### Terraform Structure

The Terraform configuration is split into logical files:

- `provider.tf` - Proxmox provider configuration using the `bpg/proxmox` provider (v0.88.0). Authentication uses SSH agent with user `terraform`. The provider connects to node `zero.fusioncloudx.home:8006`
- `backend.tf` - Local state backend (stores state in `terraform.tfstate` at project root)
- `ubuntu-template.tf` - Creates a VM template (ID 1000) from Ubuntu Noble cloud image. This downloads the image to `nas-infrastructure` datastore and creates a template with SCSI disk on `vm-data`
- `cloud-init.tf` - Defines cloud-init configuration with split user_data (per-VM) and vendor_data (shared). Stored as snippets on `nas-infrastructure` datastore
- `qemu-vm.tf` - Creates VM instances using `for_each` loop pattern to dynamically provision multiple VMs from the template. Uses 10 retries for clone operations to handle storage lock contention
- `outputs.tf` - Exports VM IPv4 addresses as a map (VM name → IP address) from QEMU guest agent
- `variables.tf` - Defines `vm_configs` map with VM specifications (ID, name, memory, CPU, started, on_boot, full_clone)

### Key Terraform Resources

**Template Creation Flow:**
1. `proxmox_virtual_environment_download_file.ubuntu-cloud-image` downloads Ubuntu Noble cloud image
2. `proxmox_virtual_environment_vm.ubuntu-template` creates template (VM ID 1000) from the downloaded image
3. Template is marked with `template = true` and `started = false`

**VM Provisioning Flow:**
1. `proxmox_virtual_environment_file.user_data_cloud_config` creates per-VM cloud-init user_data (hostname, users)
2. `proxmox_virtual_environment_file.vendor_data_cloud_config` creates shared cloud-init vendor_data (packages, timezone, commands)
3. `proxmox_virtual_environment_vm.qemu-vm` uses `for_each` to clone template 1000 with full clone for each VM in `vm_configs`
4. Cloud-init runs with split configuration on each VM

**Current VMs Provisioned (4 total):**
- **teleport** (VM ID 1101) - 2GB RAM, 2 CPU cores - Remote access service (planned)
- **semaphore** (VM ID 1102) - 2GB RAM, 2 CPU cores - Ansible UI/automation (planned)
- **wazuh** (VM ID 1103) - 4GB RAM, 2 CPU cores - SIEM/security monitoring (planned)
- **immich** (VM ID 1104) - 4GB RAM, 2 CPU cores - Photo management (planned)

All VMs are provisioned and running Ubuntu Noble base OS. Services are NOT yet installed - VMs are blank systems ready for service deployment.

### Cloud-Init Configuration

The cloud-init config uses **split configuration** for flexibility:

**User Data (per-VM in `cloud-init.tf`):**
- Sets hostname to VM name (teleport, semaphore, wazuh, immich)
- Creates user `fcx` with sudo access (NOPASSWD - appropriate for homelab/dev)
- SSH key import from GitHub user `thisisbramiller`
- Password authentication disabled (`lock_passwd: true`)

**Vendor Data (shared across all VMs):**
- Timezone: America/Chicago
- Package updates enabled
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
- VMs in `qemu-vm.tf` depend on the template in `ubuntu-template.tf` via `depends_on`
- The template must exist before cloning VMs from it
- Cloud-init files (user_data and vendor_data) must be created before VM initialization references them

### Datastores
- `nas-infrastructure` - Used for cloud images and cloud-init snippets
- `vm-data` - Used for VM disks and cloud-init configs during initialization

### VM Specifications
- Template: VM ID 1000, named "ubuntu-template", on node "zero"
- VMs are full clones (not linked clones) of the template by default
- VM configs are defined in `variables.tf` with individual CPU, memory, and startup settings
- All VMs: x86-64-v2-AES CPU type, DHCP networking, serial console enabled
- Clone operations use 10 retries to handle storage lock contention
- VMs auto-start on Proxmox host boot by default (`on_boot = true`)

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

The working branch is `multi-vm`. The main branch for PRs is `main`.

## Environment Context

**This repository manages homelab/development infrastructure, not production.** VMs are provisioned for testing and development of services. Production infrastructure will be deployed separately on AWS using dedicated Terraform configurations.
