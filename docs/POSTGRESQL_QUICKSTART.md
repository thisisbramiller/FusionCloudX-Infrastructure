# PostgreSQL Infrastructure Quick Start

This is a streamlined guide to deploy the refactored PostgreSQL LXC infrastructure with 1Password integration.

## Prerequisites

- Proxmox VE node running (node: `zero`)
- 1Password account with CLI installed
- Terraform >= 1.0 installed
- Ansible with `community.general` collection installed

## Quick Setup (30 Minutes)

### 1. Set Up 1Password (10 minutes)

```bash
# Install 1Password CLI (if not installed)
# macOS:
brew install --cask 1password-cli
# Linux: see docs/1PASSWORD_SETUP.md

# Create service account at https://my.1password.com/
# Settings > Service Accounts > Create Service Account
# Name: terraform-homelab
# Grant access to "Homelab" vault

# Export service account token
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

# Get vault ID
op vault list
# Copy the UUID for "Homelab" vault
```

### 2. Configure Terraform (5 minutes)

```bash
cd terraform/

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
onepassword_vault_id = "your-vault-uuid-here"
EOF

# Initialize Terraform (downloads providers)
terraform init
```

### 3. Deploy Infrastructure (10 minutes)

```bash
# Preview what will be created
terraform plan

# Expected resources:
# - 1 LXC container (postgresql)
# - 3 1Password items (admin, semaphore user, wazuh user)
# - 1 Debian template download

# Deploy!
terraform apply

# Get IP address
terraform output postgresql_container_ipv4
# Example: 192.168.1.45
```

### 4. Configure Ansible (5 minutes)

```bash
cd ../ansible/

# Install community.general collection
ansible-galaxy collection install community.general

# Update inventory with IP from terraform output
nano inventory/hosts.ini

# Change:
# postgresql ansible_host=192.168.1.XXX
# To actual IP from terraform output

# Test connectivity
ansible postgresql -m ping
```

### 5. Deploy PostgreSQL (10 minutes)

```bash
# Run PostgreSQL playbook
ansible-playbook playbooks/postgresql.yml

# This will:
# - Install PostgreSQL 15
# - Create databases: semaphore, wazuh
# - Create users with passwords from 1Password
# - Configure firewall
# - Start service
```

### 6. Verify Deployment (2 minutes)

```bash
# SSH to container
ssh root@192.168.1.XXX  # Use your actual IP

# Check PostgreSQL is running
systemctl status postgresql

# List databases
sudo -u postgres psql -l

# Should see:
# - postgres (default)
# - semaphore (owner: semaphore)
# - wazuh (owner: wazuh)

# Exit container
exit
```

## What Was Created

### Infrastructure

```
┌─────────────────────────────────────────┐
│ Proxmox Node: zero                      │
│                                         │
│  LXC Container ID 2001: postgresql      │
│  • Debian 12                            │
│  • 4GB RAM, 2 CPU cores, 64GB disk      │
│  • PostgreSQL 15                        │
│  • Databases: semaphore, wazuh          │
│  • Users: postgres, semaphore, wazuh    │
└─────────────────────────────────────────┘
```

### 1Password Items

```
┌─────────────────────────────────────────┐
│ 1Password Vault: Homelab                │
│                                         │
│  PostgreSQL Admin (postgres)            │
│  • username: postgres                   │
│  • password: [auto-generated 32 chars]  │
│  • hostname: postgresql.fusioncloudx    │
│  • port: 5432                           │
│                                         │
│  PostgreSQL - Semaphore Database User   │
│  • username: semaphore                  │
│  • password: [auto-generated 32 chars]  │
│  • database: semaphore                  │
│                                         │
│  PostgreSQL - Wazuh Database User       │
│  • username: wazuh                      │
│  • password: [auto-generated 32 chars]  │
│  • database: wazuh                      │
└─────────────────────────────────────────┘
```

## Testing Database Connectivity

### From Command Line

```bash
# Get password from 1Password
op item get "PostgreSQL - Semaphore Database User" --vault Homelab --fields password

# Connect to database
psql -h 192.168.1.XXX -U semaphore -d semaphore
# Enter password when prompted

# Test query
SELECT version();
```

### From Application

Configure your application to connect:

```
Host: postgresql.fusioncloudx.home (or 192.168.1.XXX)
Port: 5432
Database: semaphore (or wazuh)
Username: semaphore (or wazuh)
Password: [retrieve from 1Password]
```

## Common Tasks

### Add New Database

1. Edit `terraform/variables.tf`:
   ```hcl
   variable "postgresql_databases" {
     default = [
       # ... existing databases ...
       {
         name        = "newapp"
         description = "Database for New App"
         owner       = "newapp"
       }
     ]
   }
   ```

2. Create 1Password item in `terraform/lxc-postgresql.tf`:
   ```hcl
   resource "onepassword_item" "newapp_db_user" {
     vault    = var.onepassword_vault_id
     category = "database"
     title    = "PostgreSQL - NewApp Database User"
     tags     = ["terraform", "postgresql", "newapp", "homelab"]
     type     = "postgresql"
     hostname = "${var.postgresql_lxc_config.hostname}.fusioncloudx.home"
     port     = "5432"
     database = "newapp"
     username = "newapp"
     password_recipe {
       length  = 32
       symbols = true
     }
   }
   ```

3. Update Ansible `group_vars/postgresql.yml`:
   ```yaml
   postgresql_databases:
     # ... existing ...
     - name: "newapp"
       owner: "newapp"
       encoding: "UTF-8"
       lc_collate: "en_US.UTF-8"
       lc_ctype: "en_US.UTF-8"

   postgresql_users:
     # ... existing ...
     - name: "newapp"
       password: "{{ lookup('community.general.onepassword', 'PostgreSQL - NewApp Database User', field='password', vault='Homelab') }}"
       database: "newapp"
       priv: "ALL"
       role_attr_flags: "NOSUPERUSER,NOCREATEROLE"
   ```

4. Apply changes:
   ```bash
   terraform apply
   ansible-playbook playbooks/postgresql.yml
   ```

### Rotate Password

1. Update password in 1Password (web/app)
2. Run Ansible:
   ```bash
   ansible-playbook playbooks/postgresql.yml --tags users
   ```

### Scale Resources

Edit `terraform/variables.tf` or `terraform.tfvars`:

```hcl
postgresql_lxc_config = {
  vm_id       = 2001
  hostname    = "postgresql"
  description = "Centralized PostgreSQL database server"
  memory_mb   = 8192   # Increase RAM
  cpu_cores   = 4      # Increase CPU
  disk_gb     = 128    # Increase disk
  started     = true
  on_boot     = true
  tags        = ["database", "postgresql", "homelab"]
}
```

Apply:
```bash
terraform apply
```

### Backup Database

```bash
# SSH to container
ssh root@192.168.1.XXX

# Backup single database
sudo -u postgres pg_dump semaphore > /tmp/semaphore_backup.sql

# Backup all databases
sudo -u postgres pg_dumpall > /tmp/all_databases_backup.sql

# Copy to local machine
scp root@192.168.1.XXX:/tmp/semaphore_backup.sql ./
```

### Restore Database

```bash
# SSH to container
ssh root@192.168.1.XXX

# Restore database
sudo -u postgres psql semaphore < /tmp/semaphore_backup.sql
```

## Troubleshooting

### Can't Connect to PostgreSQL

**Check service is running:**
```bash
ssh root@192.168.1.XXX
systemctl status postgresql
```

**Check firewall:**
```bash
ufw status
# Should allow port 5432 from 192.168.0.0/16
```

**Check pg_hba.conf:**
```bash
cat /etc/postgresql/15/main/pg_hba.conf | grep 192.168
# Should have entry for 192.168.0.0/16
```

### 1Password Authentication Failed

**Verify token:**
```bash
echo $OP_SERVICE_ACCOUNT_TOKEN
# Should start with "ops_"

op vault list
# Should show your vaults
```

**Re-export token:**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"
```

### Ansible Can't Find Item in 1Password

**List items:**
```bash
op item list --vault Homelab | grep PostgreSQL
```

**Test lookup:**
```bash
ansible localhost -m debug -a "msg={{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"
```

## Next Steps

- Deploy Semaphore UI and connect to `semaphore` database
- Deploy Wazuh and connect to `wazuh` database
- Set up automated backups to NAS
- Configure monitoring (pg_stat_statements, etc.)
- Review `docs/POSTGRESQL_REFACTOR_SUMMARY.md` for detailed information

## Documentation

- **Full Setup Guide**: `docs/1PASSWORD_SETUP.md`
- **Ansible Integration**: `docs/ANSIBLE_1PASSWORD_INTEGRATION.md`
- **Detailed Summary**: `docs/POSTGRESQL_REFACTOR_SUMMARY.md`
- **Provider Docs**:
  - [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
  - [1Password/onepassword](https://registry.terraform.io/providers/1Password/onepassword/latest/docs)
