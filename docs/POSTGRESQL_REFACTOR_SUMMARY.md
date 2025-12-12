# PostgreSQL LXC Infrastructure Refactor - Summary

## Overview

This document summarizes the PostgreSQL LXC infrastructure refactor completed for FusionCloudX Infrastructure. The refactor addresses critical architectural issues and implements modern secrets management.

## Problems Solved

### 1. Architecture Issue: Multiple PostgreSQL Instances

**Previous (WRONG):**
- Separate LXC container for each service
- `postgresql-semaphore` (VM ID 2001) - 2GB RAM, 32GB disk
- `postgresql-wazuh` (VM ID 2002) - 4GB RAM, 64GB disk (commented out)
- Each container ran its own PostgreSQL instance
- Resource inefficient for homelab

**Current (CORRECT):**
- **Single LXC container** hosting multiple databases
- `postgresql` (VM ID 2001) - 4GB RAM, 64GB disk
- One PostgreSQL instance with multiple databases:
  - `semaphore` database for Semaphore UI
  - `wazuh` database for Wazuh SIEM
  - Easy to add more databases as needed
- Resource efficient, scalable architecture

**Why This Matters:**
- **Resource Efficiency**: One PostgreSQL instance uses less RAM/CPU than multiple instances
- **Easier Management**: Single container to maintain, backup, and monitor
- **Standard Practice**: This is how databases are typically run (one server, many databases)
- **Scalability**: Can scale vertically (more RAM/CPU) or add replication/HA later
- **Cost Effective**: For homelab, running one instance is more practical

### 2. Secrets Management: ansible-vault → 1Password

**Previous (WRONG):**
- `ansible-vault` for encrypting secrets in git
- Passwords stored in `vault.yml` files
- Requires vault password to decrypt
- Difficult to share secrets across team
- No audit trail of secret access
- Manual password rotation

**Current (CORRECT):**
- **1Password** for centralized secrets management
- Terraform creates 1Password items with auto-generated passwords
- Ansible retrieves secrets at runtime via 1Password CLI
- Never store secrets in git (not even encrypted)
- Full audit trail of who accessed what
- Easy password rotation
- Team sharing built-in

**Why This Matters:**
- **Security**: Secrets never touch git or disk
- **Compliance**: Audit trail for all secret access
- **Automation**: Auto-generated strong passwords
- **Collaboration**: Easy to share with team members
- **Best Practice**: Industry standard for secrets management

### 3. Provider Compliance: Proper bpg/proxmox Usage

**Improvements:**
- Verified all LXC container resource usage matches bpg/proxmox v0.88.0 specs
- Proper use of `proxmox_virtual_environment_container` resource
- Correct attribute names: `start_on_boot` (not `on_boot` in resource)
- Proper initialization block structure
- Tags support for organization

## File Changes

### Terraform Files Modified

1. **`terraform/lxc-postgresql.tf`**
   - Changed from `for_each` loop to single resource
   - Removed `lxc_postgresql_configs` variable reference
   - Added proper 1Password integration
   - Created 3 `onepassword_item` resources for credentials
   - Fixed `on_boot` → `start_on_boot` attribute

2. **`terraform/variables.tf`**
   - Replaced `lxc_postgresql_configs` (map) with `postgresql_lxc_config` (object)
   - Added `postgresql_databases` variable for database definitions
   - Added `onepassword_vault_id` variable for 1Password integration
   - Removed per-container configuration pattern

3. **`terraform/provider.tf`**
   - Added `onepassword` provider (1Password/onepassword ~> 3.0)
   - Configured authentication via environment variables
   - Added documentation comments for setup

4. **`terraform/outputs.tf`**
   - Changed from map outputs to single resource outputs
   - Added `postgresql_container_id`, `postgresql_container_hostname`, `postgresql_container_ipv4`
   - Added 1Password item ID outputs for reference
   - Added comprehensive `postgresql_deployment_summary` output

### Documentation Created

1. **`docs/1PASSWORD_SETUP.md`**
   - Complete 1Password setup guide
   - Service Account vs Connect comparison
   - Step-by-step setup instructions
   - Troubleshooting guide
   - Security best practices

2. **`docs/ANSIBLE_1PASSWORD_INTEGRATION.md`**
   - Ansible + 1Password integration guide
   - `onepassword` lookup plugin usage
   - Example configurations
   - Migration from ansible-vault
   - Advanced usage patterns

3. **`docs/POSTGRESQL_REFACTOR_SUMMARY.md`** (this file)
   - Overview of changes
   - Migration instructions
   - Architecture decisions
   - Testing procedures

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Proxmox Node: zero                           │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ LXC Container: postgresql (ID 2001)                    │   │
│  │ Debian 12, 4GB RAM, 2 cores, 64GB disk                │   │
│  │                                                         │   │
│  │  ┌──────────────────────────────────────────────────┐ │   │
│  │  │ PostgreSQL 15 Server                             │ │   │
│  │  │                                                   │ │   │
│  │  │  Database: semaphore (Owner: semaphore)          │ │   │
│  │  │  Database: wazuh (Owner: wazuh)                  │ │   │
│  │  │  Database: [future databases...]                 │ │   │
│  │  │                                                   │ │   │
│  │  │  User: postgres (admin)                          │ │   │
│  │  │  User: semaphore (app user)                      │ │   │
│  │  │  User: wazuh (app user)                          │ │   │
│  │  └──────────────────────────────────────────────────┘ │   │
│  │                                                         │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↑ ↑
                            │ │
                ┌───────────┘ └───────────┐
                │                          │
        ┌───────▼──────────┐      ┌───────▼──────────┐
        │  Semaphore VM    │      │   Wazuh VM       │
        │  (connects to    │      │  (connects to    │
        │   semaphore DB)  │      │   wazuh DB)      │
        └──────────────────┘      └──────────────────┘
```

## Migration Steps

### Step 1: Backup Current State

```bash
# Backup Terraform state
cd terraform/
cp terraform.tfstate terraform.tfstate.backup

# Backup Ansible vault (if exists)
cd ../ansible/
cp group_vars/vault.yml group_vars/vault.yml.backup 2>/dev/null || true
```

### Step 2: Destroy Old PostgreSQL Containers

**IMPORTANT**: Only do this if you haven't created databases yet!

```bash
cd terraform/

# Remove old PostgreSQL containers from state
terraform state list | grep postgresql
terraform destroy -target=proxmox_virtual_environment_container.postgresql

# Or if you want to keep data, manually export databases first:
# ssh root@postgresql-semaphore "pg_dump semaphore > /tmp/semaphore.sql"
```

### Step 3: Set Up 1Password

Follow the guide in `docs/1PASSWORD_SETUP.md`:

```bash
# Option 1: Service Account
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

# Option 2: 1Password Connect (more advanced)
# See docs/1PASSWORD_SETUP.md for Docker Compose setup
export OP_CONNECT_HOST="http://localhost:8080"
export OP_CONNECT_TOKEN="your_connect_token_here"

# Get your vault ID
op vault list
# Copy the UUID for your Homelab vault
```

### Step 4: Configure Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
# 1Password Configuration
onepassword_vault_id = "your-vault-uuid-here"

# PostgreSQL configuration is already in variables.tf defaults
# Only override if you need different values:
# postgresql_lxc_config = {
#   vm_id       = 2001
#   hostname    = "postgresql"
#   description = "Centralized PostgreSQL database server"
#   memory_mb   = 4096
#   cpu_cores   = 2
#   disk_gb     = 64
#   started     = true
#   on_boot     = true
#   tags        = ["database", "postgresql", "homelab"]
# }
```

### Step 5: Initialize and Apply Terraform

```bash
cd terraform/

# Re-initialize to download 1Password provider
terraform init -upgrade

# Preview changes
terraform plan

# Apply changes (creates 1 LXC container + 3 1Password items)
terraform apply

# Verify outputs
terraform output postgresql_deployment_summary
```

Expected output:
```
postgresql_deployment_summary = {
  container = {
    cpu = 2
    disk = 64
    hostname = "postgresql"
    id = 2001
    ip = "192.168.1.XXX"
    memory = 4096
  }
  databases = [
    {
      description = "Database for Semaphore (Ansible UI)"
      name = "semaphore"
      owner = "semaphore"
    },
    {
      description = "Database for Wazuh (SIEM)"
      name = "wazuh"
      owner = "wazuh"
    },
  ]
  secrets = {
    admin_password_1password_id = "vaults/abc123.../items/xyz789..."
    semaphore_password_1password_id = "vaults/abc123.../items/uvw456..."
    wazuh_password_1password_id = "vaults/abc123.../items/rst123..."
  }
}
```

### Step 6: Verify 1Password Items Created

```bash
# List items in vault
op item list --vault Homelab

# View an item (verify password was generated)
op item get "PostgreSQL Admin (postgres)" --vault Homelab

# Or view in 1Password app/web interface
```

### Step 7: Update Ansible Configuration

#### Update `ansible/inventory/hosts.ini`:

```ini
[postgresql]
postgresql ansible_host=192.168.1.XXX  # Use IP from terraform output

[postgresql:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
```

#### Create/Update `ansible/inventory/group_vars/postgresql.yml`:

Use the example from `docs/ANSIBLE_1PASSWORD_INTEGRATION.md`:

```yaml
---
# PostgreSQL admin password from 1Password
postgresql_admin_password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"

# Databases to create (matches Terraform variable)
postgresql_databases:
  - name: "semaphore"
    owner: "semaphore"
    encoding: "UTF-8"
    lc_collate: "en_US.UTF-8"
    lc_ctype: "en_US.UTF-8"
    template: "template0"
  - name: "wazuh"
    owner: "wazuh"
    encoding: "UTF-8"
    lc_collate: "en_US.UTF-8"
    lc_ctype: "en_US.UTF-8"
    template: "template0"

# Users to create with passwords from 1Password
postgresql_users:
  - name: "semaphore"
    password: "{{ lookup('community.general.onepassword', 'PostgreSQL - Semaphore Database User', field='password', vault='Homelab') }}"
    database: "semaphore"
    priv: "ALL"
    role_attr_flags: "CREATEDB,NOSUPERUSER,NOCREATEROLE"
  - name: "wazuh"
    password: "{{ lookup('community.general.onepassword', 'PostgreSQL - Wazuh Database User', field='password', vault='Homelab') }}"
    database: "wazuh"
    priv: "ALL"
    role_attr_flags: "NOSUPERUSER,NOCREATEROLE"

# ... rest of postgresql.yml configuration ...
```

#### Delete old host_vars files:

```bash
cd ansible/
rm inventory/host_vars/postgresql-semaphore.yml
rm inventory/host_vars/postgresql-wazuh.yml

# Keep the directory for future use
mkdir -p inventory/host_vars
```

### Step 8: Run Ansible Playbook

```bash
cd ansible/

# Install community.general collection (if not already)
ansible-galaxy collection install community.general

# Test connectivity
ansible postgresql -m ping

# Run PostgreSQL playbook
ansible-playbook playbooks/postgresql.yml

# Verify deployment
ansible postgresql -m shell -a "sudo -u postgres psql -l"
```

Expected output should show `semaphore` and `wazuh` databases.

### Step 9: Verify Deployment

```bash
# SSH to PostgreSQL container
ssh root@192.168.1.XXX  # Use IP from terraform output

# Check PostgreSQL is running
systemctl status postgresql

# List databases
sudo -u postgres psql -l

# Verify users can connect
sudo -u postgres psql -U semaphore -d semaphore -c "\conninfo"
sudo -u postgres psql -U wazuh -d wazuh -c "\conninfo"

# Check firewall
ufw status
```

### Step 10: Clean Up

```bash
# Remove old vault file (after verifying everything works!)
rm ansible/group_vars/vault.yml 2>/dev/null || true

# Remove old Terraform state backup (optional, after verification)
rm terraform/terraform.tfstate.backup
```

## Testing Procedures

### Test 1: Terraform Plan (Idempotency)

```bash
cd terraform/
terraform plan
```

Should show: `No changes. Your infrastructure matches the configuration.`

### Test 2: 1Password Secret Retrieval

```bash
# Test 1Password CLI
op item get "PostgreSQL Admin (postgres)" --vault Homelab --fields password

# Test Ansible lookup
cd ansible/
ansible localhost -m debug -a "msg={{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"
```

### Test 3: Database Connectivity

```bash
# From Semaphore VM (when deployed)
psql -h postgresql.fusioncloudx.home -U semaphore -d semaphore -c "SELECT version();"

# From Wazuh VM (when deployed)
psql -h postgresql.fusioncloudx.home -U wazuh -d wazuh -c "SELECT version();"
```

### Test 4: Password Rotation

```bash
# Update password in 1Password (via web/app)
# Then run Ansible to apply new password
cd ansible/
ansible-playbook playbooks/postgresql.yml --tags users

# Verify new password works
# (Test database connection with new credentials)
```

## Scalability Considerations

### Vertical Scaling

To add more resources to PostgreSQL container:

```hcl
# In terraform/variables.tf or terraform.tfvars
postgresql_lxc_config = {
  vm_id       = 2001
  hostname    = "postgresql"
  description = "Centralized PostgreSQL database server"
  memory_mb   = 8192   # Doubled from 4GB to 8GB
  cpu_cores   = 4      # Doubled from 2 to 4 cores
  disk_gb     = 128    # Doubled from 64GB to 128GB
  started     = true
  on_boot     = true
  tags        = ["database", "postgresql", "homelab"]
}
```

Then run:
```bash
terraform apply
# May require container restart/rebuild depending on Proxmox settings
```

### Adding New Databases

1. **Update Terraform variables**:
   ```hcl
   # In terraform/variables.tf
   variable "postgresql_databases" {
     default = [
       { name = "semaphore", description = "...", owner = "semaphore" },
       { name = "wazuh", description = "...", owner = "wazuh" },
       { name = "immich", description = "Database for Immich", owner = "immich" }  # NEW
     ]
   }
   ```

2. **Create 1Password item** (in `lxc-postgresql.tf`):
   ```hcl
   resource "onepassword_item" "immich_db_user" {
     vault    = var.onepassword_vault_id
     category = "database"
     title    = "PostgreSQL - Immich Database User"
     tags     = ["terraform", "postgresql", "immich", "homelab"]
     type     = "postgresql"
     hostname = "${var.postgresql_lxc_config.hostname}.fusioncloudx.home"
     port     = "5432"
     database = "immich"
     username = "immich"
     password_recipe {
       length  = 32
       symbols = true
     }
   }
   ```

3. **Update Ansible** (`group_vars/postgresql.yml`):
   ```yaml
   postgresql_databases:
     - name: "immich"
       owner: "immich"
       # ... config ...

   postgresql_users:
     - name: "immich"
       password: "{{ lookup('community.general.onepassword', 'PostgreSQL - Immich Database User', field='password', vault='Homelab') }}"
       database: "immich"
       # ... config ...
   ```

4. **Apply changes**:
   ```bash
   terraform apply
   ansible-playbook playbooks/postgresql.yml
   ```

### High Availability (Future)

If you outgrow single instance:

1. **PostgreSQL Replication** (Streaming Replication)
   - Create second LXC container for replica
   - Configure primary-replica replication
   - Use pgpool or HAProxy for load balancing

2. **Patroni + etcd** (Advanced HA)
   - Automated failover
   - Requires 3+ nodes for quorum
   - Better for production workloads

3. **Separate Instances per Service** (If needed)
   - Go back to multiple containers, but now with 1Password
   - Only if load/isolation requires it
   - Not recommended for homelab

## Rollback Plan

If something goes wrong:

### Rollback Terraform

```bash
cd terraform/

# Destroy new resources
terraform destroy -target=proxmox_virtual_environment_container.postgresql
terraform destroy -target=onepassword_item.postgresql_admin
terraform destroy -target=onepassword_item.semaphore_db_user
terraform destroy -target=onepassword_item.wazuh_db_user

# Restore old state
cp terraform.tfstate.backup terraform.tfstate

# Restore old configuration files
git checkout HEAD -- lxc-postgresql.tf variables.tf provider.tf outputs.tf

# Re-apply old configuration
terraform apply
```

### Rollback Ansible

```bash
cd ansible/

# Restore old vault file
cp group_vars/vault.yml.backup group_vars/vault.yml

# Restore old host_vars
git checkout HEAD -- inventory/host_vars/postgresql-semaphore.yml
git checkout HEAD -- inventory/host_vars/postgresql-wazuh.yml

# Restore old group_vars
git checkout HEAD -- inventory/group_vars/postgresql.yml
```

## Benefits Summary

1. **Resource Efficiency**: One PostgreSQL instance instead of multiple
2. **Easier Management**: Single container to maintain, backup, monitor
3. **Better Secrets**: 1Password replaces ansible-vault with modern secrets management
4. **Scalable**: Easy to add databases, scale resources, or add HA later
5. **Standard Practice**: Follows database industry best practices
6. **Audit Trail**: Full logging of secret access via 1Password
7. **Team Collaboration**: Easy to share credentials securely
8. **Automation**: Auto-generated passwords, no manual management

## Next Steps

1. **Deploy Semaphore** - Configure Semaphore UI to connect to `semaphore` database
2. **Deploy Wazuh** - Configure Wazuh to connect to `wazuh` database
3. **Set Up Backups** - Implement pg_dump backups to NAS
4. **Monitoring** - Set up PostgreSQL monitoring (pg_stat_statements, etc.)
5. **Performance Tuning** - Adjust postgresql.conf based on workload
6. **Documentation** - Update CLAUDE.md with new architecture

## Support

- See `docs/1PASSWORD_SETUP.md` for 1Password configuration help
- See `docs/ANSIBLE_1PASSWORD_INTEGRATION.md` for Ansible integration help
- Review Terraform provider docs:
  - bpg/proxmox: https://registry.terraform.io/providers/bpg/proxmox/latest/docs
  - 1Password/onepassword: https://registry.terraform.io/providers/1Password/onepassword/latest/docs
- Review Ansible collection docs:
  - community.general: https://docs.ansible.com/ansible/latest/collections/community/general/onepassword_lookup.html
