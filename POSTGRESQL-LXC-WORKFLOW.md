# PostgreSQL LXC Infrastructure - Complete Workflow

This document provides a step-by-step guide for deploying PostgreSQL database infrastructure using Terraform (infrastructure provisioning) and Ansible (configuration management).

## 🎯 Overview

We're deploying PostgreSQL database servers as LXC containers on Proxmox with proper separation of concerns:

- **Terraform**: Provisions LXC containers (infrastructure only)
- **Ansible**: Configures PostgreSQL (all software configuration)
- **Vault**: Secures passwords and secrets

## 🏗️ Architecture

### Infrastructure Components

- **postgresql-semaphore** (VM ID 2001)
  - 2GB RAM, 2 CPU cores, 32GB disk
  - PostgreSQL 15 for Semaphore (Ansible UI)
  - Database: `semaphore`, User: `semaphore`

- **postgresql-wazuh** (VM ID 2002) - OPTIONAL
  - 4GB RAM, 2 CPU cores, 64GB disk
  - PostgreSQL 15 for Wazuh (SIEM)
  - Database: `wazuh`, User: `wazuh`

### Technology Stack

- **Platform**: Proxmox VE (node: zero.fusioncloudx.home)
- **Containers**: Debian 12 LXC (unprivileged)
- **Database**: PostgreSQL 15
- **IaC**: Terraform v1.x with `bpg/proxmox` provider v0.88.0
- **Config Mgmt**: Ansible 2.x
- **Security**: ansible-vault for secret management

## 📋 Prerequisites

### 1. Development Environment

```bash
# Required tools
- Terraform >= 1.0
- Ansible >= 2.9
- Python 3
- SSH access to Proxmox node
- jq (for inventory update scripts)

# Verify installations
terraform --version
ansible --version
python3 --version
jq --version
```

### 2. Proxmox Setup

- Proxmox VE node accessible at `zero.fusioncloudx.home:8006`
- Terraform user with API access (SSH agent authentication)
- Datastores: `nas-infrastructure` (templates), `vm-data` (disks)

### 3. SSH Keys

```bash
# Ensure SSH key is available for LXC container access
ls -la ~/.ssh/id_rsa.pub

# If not exists, generate one
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

## 🚀 Complete Deployment Workflow

### Phase 1: Provision Infrastructure (Terraform)

#### Step 1: Review Configuration

```bash
cd terraform

# Review LXC container configurations
cat variables.tf | grep -A 20 "lxc_postgresql_configs"

# Expected output shows:
# - postgresql-semaphore (VM ID 2001)
# - postgresql-wazuh (VM ID 2002) - commented out initially
```

#### Step 2: Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Expected output: Provider bpg/proxmox v0.88.0 installed
```

#### Step 3: Plan Infrastructure

```bash
# Review what will be created
terraform plan

# You should see:
# + proxmox_virtual_environment_download_file.debian12_lxc_template
# + proxmox_virtual_environment_container.postgresql["postgresql-semaphore"]
```

#### Step 4: Deploy Infrastructure

```bash
# Create the LXC containers
terraform apply

# Type 'yes' to confirm

# Wait for completion (~2-5 minutes)
```

#### Step 5: Verify Infrastructure

```bash
# Check outputs
terraform output

# You should see:
# - lxc_postgresql_ipv4_addresses (container IPs)
# - ansible_inventory_postgresql (formatted for Ansible)

# Verify containers in Proxmox
ssh terraform@zero.fusioncloudx.home
pct list | grep postgresql
```

### Phase 2: Configure Ansible

#### Step 1: Set Up Vault

```bash
cd ../ansible

# Option A: Use setup script (recommended)
./setup-vault.sh

# Option B: Manual setup
echo "$(openssl rand -base64 32)" > .vault_pass
chmod 600 .vault_pass
ansible-vault encrypt inventory/group_vars/vault.yml
```

#### Step 2: Update Passwords

```bash
# Edit encrypted vault file
ansible-vault edit inventory/group_vars/vault.yml

# Update these passwords with strong values:
# vault_postgresql_admin_password: "YourStrongPostgresPassword"
# vault_semaphore_db_password: "YourStrongSemaphorePassword"
# vault_wazuh_db_password: "YourStrongWazuhPassword"

# Save and exit (usually :wq in vim)
```

**Password Best Practices:**
- Use 32+ character passwords
- Include uppercase, lowercase, numbers, symbols
- Generate with: `openssl rand -base64 32`
- Never reuse passwords across systems

#### Step 3: Update Inventory

```bash
# Extract IPs from Terraform and update Ansible inventory

# On Linux/Mac/WSL:
./update-inventory.sh

# On Windows PowerShell:
.\update-inventory.ps1

# Verify inventory was updated
cat inventory/hosts.ini

# You should see:
# [postgresql]
# postgresql-semaphore ansible_host=192.168.X.X
```

#### Step 4: Test Connectivity

```bash
# Test SSH connectivity to all PostgreSQL hosts
ansible postgresql -m ping

# Expected output:
# postgresql-semaphore | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }

# If connection fails, troubleshoot:
ansible postgresql -m ping -vvv  # Verbose output
ssh root@<container-ip>          # Manual SSH test
```

### Phase 3: Deploy PostgreSQL (Ansible)

#### Step 1: Dry Run

```bash
# Check what would change (without making changes)
ansible-playbook playbooks/postgresql.yml --check

# Review the output for any errors
```

#### Step 2: Deploy to First Host

```bash
# Deploy to postgresql-semaphore only
ansible-playbook playbooks/postgresql.yml --limit postgresql-semaphore

# Monitor the output for:
# ✓ Package installation
# ✓ PostgreSQL configuration
# ✓ Database creation
# ✓ User creation
# ✓ Firewall rules

# Expected duration: 3-5 minutes
```

#### Step 3: Verify Deployment

```bash
# Run verification tasks
ansible-playbook playbooks/postgresql.yml --limit postgresql-semaphore --tags verify

# Manual verification
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c '\l'" -b

# Expected output shows:
# semaphore database with owner semaphore
```

#### Step 4: Test Database Access

```bash
# Connect to the container
ssh root@<postgresql-semaphore-ip>

# Test as postgres user
sudo -u postgres psql

# List databases
\l

# Connect to semaphore database
\c semaphore

# List tables (should be empty for now)
\dt

# Check user permissions
\du

# Exit
\q
exit
```

#### Step 5: Deploy to Additional Hosts (Optional)

```bash
# When ready to deploy postgresql-wazuh:

# 1. Uncomment in terraform/variables.tf
# 2. Apply Terraform: cd terraform && terraform apply
# 3. Update inventory: cd ../ansible && ./update-inventory.sh
# 4. Deploy: ansible-playbook playbooks/postgresql.yml --limit postgresql-wazuh
```

### Phase 4: Application Integration

#### Semaphore Connection

Once Semaphore is deployed, configure it to connect to the database:

```bash
# From Semaphore application (semaphore-ui VM)
Host: <postgresql-semaphore-ip>
Port: 5432
Database: semaphore
User: semaphore
Password: <vault_semaphore_db_password>
```

#### Wazuh Connection (Future)

```bash
# From Wazuh application
Host: <postgresql-wazuh-ip>
Port: 5432
Database: wazuh
User: wazuh
Password: <vault_wazuh_db_password>
```

## 🔧 Maintenance Tasks

### Update PostgreSQL Configuration

```bash
# 1. Edit configuration
vim ansible/inventory/group_vars/postgresql.yml
# OR for host-specific changes:
vim ansible/inventory/host_vars/postgresql-semaphore.yml

# 2. Apply changes
ansible-playbook playbooks/postgresql.yml --tags config

# 3. Verify
ansible postgresql -m systemd -a "name=postgresql state=started" -b
```

### Add a New Database

```bash
# 1. Edit host vars
vim ansible/inventory/host_vars/postgresql-semaphore.yml

# Add to postgresql_databases:
# - name: "newdb"
#   owner: "newuser"

# Add to postgresql_users:
# - name: "newuser"
#   password: "{{ vault_newdb_password }}"
#   database: "newdb"

# 2. Add password to vault
ansible-vault edit inventory/group_vars/vault.yml
# Add: vault_newdb_password: "secure_password"

# 3. Apply changes
ansible-playbook playbooks/postgresql.yml --tags databases,users
```

### Backup Databases

```bash
# Manual backup
ansible postgresql-semaphore -m shell -a "sudo -u postgres pg_dump semaphore > /tmp/semaphore_backup.sql" -b

# Retrieve backup
scp root@<postgresql-semaphore-ip>:/tmp/semaphore_backup.sql ./backups/

# Future: Automated backups will be configured via Ansible role
```

### Restart PostgreSQL

```bash
# Restart on all hosts
ansible postgresql -m systemd -a "name=postgresql state=restarted" -b

# Restart on specific host
ansible postgresql-semaphore -m systemd -a "name=postgresql state=restarted" -b
```

### Check PostgreSQL Logs

```bash
# View recent logs
ansible postgresql-semaphore -m shell -a "tail -50 /var/log/postgresql/postgresql-*.log" -b

# Search for errors
ansible postgresql -m shell -a "grep ERROR /var/log/postgresql/postgresql-*.log" -b
```

## 🐛 Troubleshooting

### Issue: Terraform can't connect to Proxmox

```bash
# Verify SSH agent has key loaded
ssh-add -l

# Test manual connection
ssh terraform@zero.fusioncloudx.home

# Check Proxmox API
curl -k https://zero.fusioncloudx.home:8006/
```

### Issue: Ansible can't connect to containers

```bash
# Verify container is running
ssh terraform@zero.fusioncloudx.home
pct list | grep postgresql
pct status 2001

# Test SSH manually
ssh root@<container-ip>

# Check SSH key in container
ssh root@<container-ip> "cat ~/.ssh/authorized_keys"

# Re-run inventory update
./update-inventory.sh
```

### Issue: Vault password errors

```bash
# Verify vault password file
ls -la .vault_pass
cat .vault_pass

# Test decryption
ansible-vault view inventory/group_vars/vault.yml

# If password is wrong, decrypt and re-encrypt
ansible-vault decrypt inventory/group_vars/vault.yml --ask-vault-pass
# Edit passwords
ansible-vault encrypt inventory/group_vars/vault.yml
```

### Issue: PostgreSQL won't start

```bash
# Check logs
ansible postgresql-semaphore -m shell -a "journalctl -u postgresql -n 50" -b

# Check configuration syntax
ansible postgresql-semaphore -m shell -a "sudo -u postgres /usr/lib/postgresql/15/bin/postgres -C config_file" -b

# Verify disk space
ansible postgresql -m shell -a "df -h" -b
```

### Issue: Database connection refused

```bash
# Check PostgreSQL is listening
ansible postgresql-semaphore -m shell -a "ss -tlnp | grep 5432" -b

# Check pg_hba.conf
ansible postgresql-semaphore -m shell -a "cat /etc/postgresql/15/main/pg_hba.conf" -b

# Check firewall
ansible postgresql-semaphore -m shell -a "ufw status" -b

# Test connection from application server
telnet <postgresql-ip> 5432
```

## 📊 Monitoring & Performance

### Check Database Size

```bash
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c \"SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database;\"" -b
```

### Check Active Connections

```bash
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c \"SELECT count(*) FROM pg_stat_activity;\"" -b
```

### Performance Tuning

Edit `ansible/inventory/host_vars/postgresql-*.yml`:

```yaml
# For 2GB RAM host
postgresql_instance_config:
  shared_buffers: "512MB"      # ~25% of RAM
  effective_cache_size: "1536MB"  # ~75% of RAM
  work_mem: "8MB"
  maintenance_work_mem: "128MB"

# For 4GB RAM host
postgresql_instance_config:
  shared_buffers: "1GB"
  effective_cache_size: "3GB"
  work_mem: "16MB"
  maintenance_work_mem: "256MB"
```

Apply changes:
```bash
ansible-playbook playbooks/postgresql.yml --tags config
```

## 🔒 Security Hardening

### Current Security Measures

✅ Unprivileged LXC containers
✅ ansible-vault encrypted passwords
✅ SCRAM-SHA-256 authentication
✅ Network-restricted access (192.168.0.0/16)
✅ UFW firewall enabled
✅ Password authentication disabled (SSH keys only)

### Additional Security Recommendations

1. **SSL/TLS Encryption**: Enable SSL for PostgreSQL connections
2. **Fail2ban**: Install fail2ban to prevent brute force attacks
3. **Regular Updates**: Schedule automatic security updates
4. **Backup Encryption**: Encrypt database backups
5. **Audit Logging**: Enable PostgreSQL audit logging
6. **Network Segmentation**: Use VLANs to isolate database traffic

## 📚 Next Steps

1. ✅ **Complete This Workflow**: Deploy PostgreSQL infrastructure
2. ⏭️ **Deploy Semaphore**: Install Semaphore UI and connect to database
3. ⏭️ **Configure Backups**: Set up automated database backups
4. ⏭️ **Enable Monitoring**: Add Prometheus + Grafana monitoring
5. ⏭️ **Deploy Wazuh**: Install Wazuh SIEM and connect to database

## 🎓 Learning Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/15/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [LXC Containers](https://linuxcontainers.org/lxc/introduction/)

---

**Built with ☕ and NetworkChuck energy for the FusionCloudX homelab!**

*Remember: We're not just building infrastructure - we're learning, experimenting, and having fun! Break things, fix them, and document what you learn. That's the homelab way!*
