# LXC Template Setup Guide

## Overview

This guide explains the **fully automated** custom Ansible-ready LXC template for PostgreSQL and other containers that require Ansible management. **No manual steps required** - Terraform handles everything.

## Why a Custom Template?

**Problem**: The bpg/proxmox Terraform provider's LXC initialization block doesn't support:
- Cloud-init (VM-only feature)
- Startup scripts
- Post-creation provisioning hooks

**Solution**: Create a custom LXC template with required packages pre-installed:
- `sudo` - For Ansible privilege escalation
- `python3` - For Ansible modules
- `python3-pip` - For Python dependencies
- `ssh-import-id` - For GitHub SSH key import
- Common utilities (curl, wget, ca-certificates, gnupg)

## How It Works (Fully Automated)

**Terraform automation** (`terraform/lxc-template-automation.tf`):
1. Detects if the template creation script has changed (via MD5 hash)
2. Copies `scripts/create-ansible-ready-lxc-template.sh` to Proxmox host via SCP
3. Executes the script on Proxmox via SSH
4. Cleans up temporary files
5. PostgreSQL LXC container creation waits for template via `depends_on`

**Prerequisites** (automatically handled):
- SSH access to Proxmox host (192.168.40.206) - uses SSH agent
- Base Debian 12 template downloaded on Proxmox - script downloads if missing

## Terraform Configuration

The Terraform configuration automatically creates and uses the custom template:

```hcl
# terraform/lxc-template-automation.tf
# Automatically creates the template on Proxmox
resource "null_resource" "create_ansible_ready_template" {
  triggers = {
    script_hash = filemd5("${path.module}/../scripts/create-ansible-ready-lxc-template.sh")
  }

  provisioner "local-exec" {
    command = "scp ... && ssh ... (creates template)"
  }
}

# terraform/lxc-postgresql.tf
# Uses the automatically-created template
resource "proxmox_virtual_environment_container" "postgresql" {
  depends_on = [null_resource.create_ansible_ready_template]

  operating_system {
    template_file_id = "nas-infrastructure:vztmpl/debian-12-ansible-ready.tar.zst"
    type             = "debian"
  }
}
```

## Deploy with Terraform (One Command)

```bash
cd terraform/

# Initialize (if needed)
terraform init

# Plan - will show template creation + container creation
terraform plan

# Apply - automatically creates template, then container
terraform apply
```

**What happens during `terraform apply`**:
1. **Template creation** (null_resource): Script runs on Proxmox, creates template (~2-3 minutes)
2. **Container creation**: PostgreSQL LXC created from template (~30 seconds)
3. **1Password items**: Database credentials generated

## Verify Container Provisioning

After Terraform creates the container:

```bash
# Get container IP
terraform output postgresql_container_ipv4

# SSH to container (should work with GitHub keys)
ssh root@<container-ip>

# Verify packages are installed
which sudo python3 pip3 ssh-import-id

# Check marker file
cat /etc/ansible-ready
```

## Template Maintenance

### Updating the Template (Fully Automated)

When you need to update packages or add new ones:

1. Modify `scripts/create-ansible-ready-lxc-template.sh`
2. Run `terraform apply` - Terraform detects the change (MD5 hash) and recreates the template
3. Existing containers won't be affected
4. New containers will use the updated template

**No manual steps** - Terraform handles everything through the null_resource trigger

### Template Location

- **Storage**: `nas-infrastructure`
- **Path**: `/var/lib/vz/template/cache/debian-12-ansible-ready.tar.zst`
- **Type**: LXC template (CT Template)

## Troubleshooting

### Template Creation Fails

**Error**: "Container already exists"
```bash
# Destroy the temp container
pct destroy 9000
# Re-run the script
```

**Error**: "Base template not found"
```bash
# Download base Debian template
pveam update
pveam available | grep debian-12
pveam download nas-infrastructure debian-12-standard_12.12-1_amd64.tar.zst
```

### SSH Access Issues

**Problem**: Can't SSH to container after creation

1. Check if SSH keys are in authorized_keys:
   ```bash
   pct exec 2001 -- cat /root/.ssh/authorized_keys
   ```

2. Manually add keys if needed:
   ```bash
   pct exec 2001 -- ssh-import-id gh:thisisbramiller
   ```

### Ansible Connection Fails

**Error**: "No module named 'ansible.module_utils.basic'"

```bash
# Verify Python is installed
pct exec 2001 -- python3 --version

# Verify sudo is installed
pct exec 2001 -- which sudo
```

## Alternative Approaches Considered

### ❌ Terraform Provisioners
- **Issue**: Requires SSH access before provisioning runs
- **Chicken-and-egg**: Can't provision SSH keys if SSH doesn't work

### ❌ Cloud-Init
- **Issue**: LXC containers don't support cloud-init
- **Only VMs**: Cloud-init is a QEMU/KVM feature

### ❌ Post-Creation Scripts
- **Issue**: Terraform provider doesn't support hooks/scripts
- **Manual**: Requires external orchestration

### ✅ Custom Template (Chosen Solution)
- **Clean**: Infrastructure-as-code principles
- **Repeatable**: Same template for all containers
- **Fast**: No per-container provisioning needed
- **Maintainable**: Update template, not individual containers

## Integration with Ansible

The custom template ensures Ansible can immediately manage the container:

```yaml
# ansible/inventory/hosts.ini
[postgresql]
postgresql ansible_host=192.168.40.xxx

[postgresql:vars]
ansible_user=root  # Custom template has root SSH access
ansible_python_interpreter=/usr/bin/python3
```

Run Ansible playbooks immediately after Terraform:

```bash
cd ansible/
ansible postgresql -m ping  # Should work immediately
ansible-playbook playbooks/postgresql.yml
```

## Summary

✅ **One-time setup**: Create custom template on Proxmox
✅ **Automated deployment**: Terraform provisions container with all packages
✅ **Immediate Ansible access**: No manual provisioning needed
✅ **Infrastructure-as-code**: Repeatable, version-controlled, automated

This is the "right way" to handle LXC container provisioning with Terraform and Ansible.
