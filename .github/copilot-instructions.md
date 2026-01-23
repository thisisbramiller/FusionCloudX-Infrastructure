# GitHub Copilot Instructions for FusionCloudX Infrastructure

This is an Infrastructure as Code (IaC) repository for managing Proxmox Virtual Environment using Terraform and Ansible.

## Project Context

- **Company**: TyDell Miller Projects, LLC DBA FusionCloud Innovations (FusionCloudX)
- **Purpose**: Production infrastructure provisioning and configuration management
- **Tech Stack**: Terraform (bpg/proxmox provider), Ansible, Cloud-init
- **Target Platform**: Proxmox VE on node "192.168.40.206"

## Code Style & Conventions

### Terraform
- Use consistent indentation (2 spaces)
- Organize configurations into logical files (provider, backend, resources)
- Use descriptive resource names
- Add comments for complex logic or workarounds
- Always use depends_on for resource dependencies
- Include descriptions for variables and outputs

### Ansible
- Follow YAML best practices
- Use roles for reusable configuration
- Include handlers for service management
- Document role purposes and variables

## Infrastructure Patterns

- VMs are provisioned by cloning from template (ID 1000)
- Cloud-init handles initial configuration (user creation, package installation)
- QEMU guest agent required for IP address discovery
- All VMs use DHCP on vmbr0 network
- Default specs: 4 cores, 2GB RAM, SeaBIOS

## Security Notes

- SSH authentication uses agent-based auth (user: terraform)
- TLS verification disabled (insecure = true) - for lab/dev only
- Cloud-init creates 'fcx' user with passwordless sudo - restrict for production
- No credentials should be committed to git

## Common Tasks

Suggest these when relevant:
- `terraform init` - Initialize Terraform
- `terraform plan` - Preview changes
- `terraform apply` - Apply infrastructure changes
- `ansible-playbook playbooks/site.yml` - Run Ansible configuration

## File Organization

- `terraform/` - All Terraform configuration files
- `ansible/` - Ansible playbooks, roles, and inventory
- `CLAUDE.md` - AI code assistant context and architecture details
- `README.md` - User-facing documentation
