# FusionCloudX Infrastructure - Ansible Configuration

This directory contains Ansible automation for configuring and managing FusionCloudX homelab infrastructure. It follows industry best practices with proper separation of concerns, **1Password secret management**, and idempotent playbooks.

## Architecture Overview

### PostgreSQL Database Server - Single Container, Multiple Databases

The infrastructure uses a **SINGLE PostgreSQL LXC container** (VM ID 2001, hostname: `postgresql`) that hosts **MULTIPLE databases** for different services:

- **semaphore** - Database for Semaphore (Ansible UI)
- **wazuh** - Database for Wazuh (SIEM)
- Additional databases can be easily added

**Container Specifications:**
- 4GB RAM
- 2 CPU cores
- 64GB disk
- Debian 12 (PostgreSQL 15)
- Optimized tuning for multiple databases

This approach provides:
- Centralized database management
- Efficient resource utilization
- Simplified backup and maintenance
- Easy scaling for additional services

## 📁 Directory Structure

```
ansible/
├── ansible.cfg                 # Ansible configuration
├── inventory/
│   ├── hosts.ini              # Inventory file (auto-updated from Terraform)
│   ├── group_vars/
│   │   ├── all.yml           # Global variables for all hosts
│   │   └── postgresql.yml    # PostgreSQL group variables
│   └── host_vars/
│       └── postgresql.yml     # SINGLE PostgreSQL host configuration
├── roles/
│   └── postgresql/            # PostgreSQL installation and configuration role
│       ├── defaults/          # Default variables
│       ├── tasks/             # Task definitions
│       ├── handlers/          # Service handlers
│       └── templates/         # Configuration templates
├── playbooks/
│   ├── site.yml              # Main orchestration playbook
│   └── postgresql.yml        # PostgreSQL deployment playbook
├── update-inventory.sh        # Bash script to update inventory from Terraform
├── update-inventory.ps1       # PowerShell script to update inventory from Terraform
└── README.md                  # This file
```

## 🚀 Quick Start

### 1. Install Prerequisites

**Ansible and Required Collections:**

```bash
# Install Ansible (if not already installed)
# macOS
brew install ansible

# Linux
sudo apt install ansible  # Debian/Ubuntu
sudo yum install ansible   # RHEL/CentOS

# Install required Ansible collections
cd ansible
ansible-galaxy collection install -r requirements.yml
```

This installs the official **1Password Connect collection** (`onepassword.connect`).

### 2. Setup 1Password Authentication

The official 1Password Connect collection supports two authentication methods:

#### Option A: 1Password Connect Server (Recommended for Homelab)

1. Deploy 1Password Connect Server (self-hosted):
   - Follow: https://developer.1password.com/docs/connect/get-started/

2. Set environment variables:

```bash
export OP_CONNECT_HOST="http://your-connect-server:8080"
export OP_CONNECT_TOKEN="your-connect-token"
```

#### Option B: 1Password Service Account (Simpler Alternative)

1. Create a Service Account in 1Password:
   - Go to: https://start.1password.com/integrations/infrastructure

2. Set environment variable:

```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token"
```

**Verify Authentication:**

```bash
# Test lookup
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

### 3. Configure Environment Variables (Persistence)

For persistent authentication, add to your shell profile:

```bash
# ~/.bashrc or ~/.zshrc (Linux/macOS)
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token"

# Or for Connect Server
export OP_CONNECT_HOST="http://your-connect-server:8080"
export OP_CONNECT_TOKEN="your-connect-token"
```

On Windows (PowerShell):

```powershell
# $PROFILE
$env:OP_SERVICE_ACCOUNT_TOKEN = "ops_your_service_account_token"
```

### 4. Update Inventory from Terraform

After deploying the LXC container with Terraform, update the Ansible inventory:

```bash
# On Linux/Mac/WSL
cd ansible
./update-inventory.sh

# On Windows PowerShell
cd ansible
.\update-inventory.ps1
```

This script extracts the PostgreSQL container IP from Terraform outputs and updates `inventory/hosts.ini`.

### 5. Test Connectivity

Verify Ansible can connect to the PostgreSQL host:

```bash
# Ping the PostgreSQL host
ansible postgresql -m ping

# Expected output:
# postgresql | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

### 6. Deploy PostgreSQL

Run the PostgreSQL deployment playbook:

```bash
# Deploy PostgreSQL with all databases
ansible-playbook playbooks/postgresql.yml

# Check what would change (dry run)
ansible-playbook playbooks/postgresql.yml --check

# Run with verbose output
ansible-playbook playbooks/postgresql.yml -v
```

## 🔐 1Password Integration

All credentials are managed via **1Password Connect** (NOT ansible-vault or 1Password CLI).

### Authentication Methods

This configuration uses the **official 1Password Connect Ansible collection** (`onepassword.connect`):
- **Connect Server**: Self-hosted 1Password Connect (recommended for homelab)
- **Service Account**: Direct API access via token (simpler setup)

See the Quick Start section for authentication setup.

### Required 1Password Items

Create these items in the **"FusionCloudX Infrastructure"** vault:

1. **PostgreSQL Admin (postgres)**
   - Field: `password` - Superuser password

2. **PostgreSQL - Semaphore DB User**
   - Field: `username` = `semaphore`
   - Field: `password` - Semaphore database user password

3. **PostgreSQL - Wazuh DB User**
   - Field: `username` = `wazuh`
   - Field: `password` - Wazuh database user password

### Credential Lookup in Ansible

Variables use the **official 1Password Connect lookup plugin**:

```yaml
password: "{{ lookup('onepassword.connect.generic_item', 'ITEM_NAME', field='password', vault='FusionCloudX Infrastructure') }}"
```

### Testing 1Password Lookups

```bash
# Ensure environment variables are set
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"
# OR
export OP_CONNECT_HOST="http://connect-server:8080"
export OP_CONNECT_TOKEN="your-token"

# Test lookup manually
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

## 📊 PostgreSQL Role

The PostgreSQL role handles complete database server setup:

### What it Does

1. **Installation**: Installs PostgreSQL 15 and required packages
2. **Configuration**: Applies optimized settings from templates
3. **Authentication**: Configures `pg_hba.conf` for secure access
4. **Database Creation**: Creates ALL application databases
5. **User Management**: Creates ALL database users with proper privileges
6. **Firewall**: Configures UFW rules for PostgreSQL access
7. **Verification**: Validates the deployment

### Configuration Files

PostgreSQL configuration is split across multiple files:

- **Group Vars** (`inventory/group_vars/postgresql.yml`): Shared configuration for the PostgreSQL server
- **Host Vars** (`inventory/host_vars/postgresql.yml`): Single host with multiple database definitions
- **1Password**: All passwords stored securely in 1Password vault

### Single-Host, Multi-Database Configuration

The `inventory/host_vars/postgresql.yml` file defines:

**PostgreSQL Tuning (4GB RAM):**
- shared_buffers: 1GB (~25% of RAM)
- effective_cache_size: 3GB (~75% of RAM)
- work_mem: 16MB (conservative for multiple databases)
- max_connections: 200 (support multiple services)

**Databases:**
```yaml
postgresql_databases:
  - name: "semaphore"
    owner: "semaphore"
    # ...
  - name: "wazuh"
    owner: "wazuh"
    # ...
```

**Users with 1Password:**
```yaml
postgresql_users:
  - name: "semaphore"
    password: "{{ lookup('onepassword.connect.generic_item', '...') }}"
    # ...
  - name: "wazuh"
    password: "{{ lookup('onepassword.connect.generic_item', '...') }}"
    # ...
```

## 🎯 Common Tasks

### Deploy PostgreSQL

```bash
# Full deployment
ansible-playbook playbooks/postgresql.yml

# With tags
ansible-playbook playbooks/postgresql.yml --tags install
ansible-playbook playbooks/postgresql.yml --tags config
ansible-playbook playbooks/postgresql.yml --tags databases,users

# Verification only
ansible-playbook playbooks/postgresql.yml --tags verify
```

### Ad-hoc Commands

```bash
# Check PostgreSQL version
ansible postgresql -m shell -a "psql --version" --become --become-user=postgres

# Check service status
ansible postgresql -m systemd -a "name=postgresql state=started" --become

# List databases
ansible postgresql -m postgresql_query -a "db=postgres login_user=postgres query='SELECT datname FROM pg_database WHERE datistemplate = false;'" --become --become-user=postgres

# Restart PostgreSQL
ansible postgresql -m systemd -a "name=postgresql state=restarted" --become
```

### View Container Details

```bash
# Check Terraform outputs
cd terraform
terraform output postgresql_deployment_summary

# Or just the IP
terraform output postgresql_container_ipv4
```

## 🔄 Workflow: Terraform → Ansible

This is the recommended workflow for infrastructure deployment:

```bash
# 1. Provision PostgreSQL LXC container with Terraform
cd terraform
terraform init
terraform plan
terraform apply

# 2. Update Ansible inventory from Terraform outputs
cd ../ansible
./update-inventory.sh  # or update-inventory.ps1 on Windows

# 3. Configure 1Password authentication
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"
# OR use Connect Server
export OP_CONNECT_HOST="http://connect-server:8080"
export OP_CONNECT_TOKEN="your-token"

# 4. Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# 5. Test connectivity
ansible postgresql -m ping

# 6. Deploy PostgreSQL
ansible-playbook playbooks/postgresql.yml

# 7. Verify deployment
ansible-playbook playbooks/postgresql.yml --tags verify
```

## 🛠️ Adding a New Database

To add a new database to the existing PostgreSQL container:

### 1. Update Terraform (Optional)

If you want to track the database in Terraform configuration:

`terraform/variables.tf`:
```hcl
variable "postgresql_databases" {
  default = [
    # ... existing databases ...
    {
      name        = "newapp"
      description = "Database for NewApp"
      owner       = "newapp"
    }
  ]
}
```

Then apply:
```bash
cd terraform
terraform apply
```

### 2. Create 1Password Item

In 1Password vault "FusionCloudX Infrastructure":

- Name: `PostgreSQL - NewApp DB User`
- Field: `username` = `newapp`
- Field: `password` = (generate strong password)

### 3. Update Ansible Configuration

Edit `ansible/inventory/host_vars/postgresql.yml`:

```yaml
postgresql_databases:
  # ... existing ...
  - name: "newapp"
    owner: "newapp"
    encoding: "UTF-8"
    lc_collate: "en_US.UTF-8"
    lc_ctype: "en_US.UTF-8"
    template: "template0"
    description: "Database for NewApp"

postgresql_users:
  # ... existing ...
  - name: "newapp"
    password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL - NewApp DB User', field='password', vault='FusionCloudX Infrastructure') }}"
    database: "newapp"
    priv: "ALL"
    role_attr_flags: "CREATEDB,NOSUPERUSER,NOCREATEROLE"
    description: "NewApp database user"

postgresql_backup_databases:
  # ... existing ...
  - newapp
```

### 4. Run Ansible

```bash
cd ansible
ansible-playbook playbooks/postgresql.yml --tags databases,users
```

## 📝 Variables Reference

### Global Variables (all.yml)

- `timezone`: System timezone (default: America/Chicago)
- `dns_nameservers`: DNS servers
- `firewall_enabled`: Enable UFW firewall

### PostgreSQL Group Variables (postgresql.yml)

- `postgresql_version`: PostgreSQL version (default: 15)
- `postgresql_global_config`: Configuration applied to the instance
- `postgresql_hba_entries`: Authentication rules (pg_hba.conf)
- `postgresql_packages`: Packages to install

### Host Variables (postgresql.yml)

- `postgresql_instance_config`: Instance-specific tuning (4GB RAM optimized)
- `postgresql_databases`: List of databases to create
- `postgresql_users`: List of database users to create (with 1Password lookups)
- `postgresql_admin_password`: Admin (postgres) user password from 1Password
- `postgresql_firewall_rules`: UFW rules
- `postgresql_backup_enabled`: Enable/disable backups
- `postgresql_backup_databases`: List of databases to backup

## 🔒 Security Considerations

### Network Access

- PostgreSQL listens on **all interfaces** (`0.0.0.0`)
- Firewall restricts access to **192.168.0.0/16** (local network only)
- Authentication via **scram-sha-256** (secure password hashing)
- No external access allowed

### Credential Management

- **NO credentials in version control**
- All passwords stored in **1Password**
- Ansible uses **runtime lookups** (credentials never stored on disk)
- `no_log: true` prevents password logging in playbook output

### SSH Access

- Root SSH access for Ansible (standard for LXC containers)
- SSH key authentication only (configured by Terraform cloud-init)
- Host key checking disabled (acceptable for homelab environment)

## 🐛 Troubleshooting

### 1Password Authentication Issues

```bash
# Check environment variables
echo $OP_SERVICE_ACCOUNT_TOKEN
# OR
echo $OP_CONNECT_HOST
echo $OP_CONNECT_TOKEN

# Test lookup with official collection
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"

# Verify collection is installed
ansible-galaxy collection list | grep onepassword

# Reinstall if needed
ansible-galaxy collection install onepassword.connect --force
```

### Connection Issues

```bash
# Test SSH directly
ssh root@192.168.1.XXX

# Test with Ansible (verbose)
ansible postgresql -m ping -vvv

# Check inventory
ansible-inventory --list

# Verify inventory file
cat inventory/hosts.ini
```

### PostgreSQL Role Failures

```bash
# Run with maximum verbosity
ansible-playbook playbooks/postgresql.yml -vvv

# Check PostgreSQL logs
ansible postgresql -m shell -a "tail -50 /var/log/postgresql/postgresql-*.log" --become

# Check service status
ansible postgresql -m shell -a "systemctl status postgresql" --become

# Test database connection
ansible postgresql -m shell -a "sudo -u postgres psql -c 'SELECT version();'" --become
```

### Inventory Not Updating

```bash
# Manually check Terraform outputs
cd terraform
terraform output ansible_inventory_postgresql

# Check if jq is installed (required for update-inventory.sh)
which jq  # Linux/macOS
where.exe jq  # Windows

# Manually parse output
terraform output -json ansible_inventory_postgresql | jq '.'
```

## 🚨 Migration Notes

**Previous Architecture v1 (Deprecated - 2025-12-12):**
- Multiple PostgreSQL containers (postgresql-semaphore, postgresql-wazuh)
- Each service had its own dedicated container
- Used ansible-vault for credentials

**Previous Architecture v2 (Deprecated - 2025-12-12):**
- Used community.general.onepassword (1Password CLI integration)
- Required op CLI tool installed and signed in
- Direct CLI command execution

**Current Architecture:**
- **SINGLE** PostgreSQL container (hostname: `postgresql`)
- Multiple databases on one instance
- **Official 1Password Connect collection** (`onepassword.connect`)
- Service Account or Connect Server authentication
- No 1Password CLI required
- Simplified inventory and configuration

**Deleted files:**
- `inventory/host_vars/postgresql-semaphore.yml`
- `inventory/host_vars/postgresql-wazuh.yml`
- `inventory/group_vars/vault.yml`
- `setup-vault.sh`

**Migrated from:**
- `community.general.onepassword` → `onepassword.connect.generic_item`
- 1Password CLI authentication → Service Account or Connect Server
- Manual `op signin` → Environment variables (OP_SERVICE_ACCOUNT_TOKEN or OP_CONNECT_HOST/TOKEN)

## 📚 Additional Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [PostgreSQL 15 Documentation](https://www.postgresql.org/docs/15/)
- [1Password Connect Documentation](https://developer.1password.com/docs/connect/)
- [1Password Connect Ansible Collection](https://github.com/1Password/ansible-onepasswordconnect-collection)
- [1Password Connect Ansible Collection Usage Guide](https://github.com/1Password/ansible-onepasswordconnect-collection/blob/main/USAGEGUIDE.md)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

## 🤝 Contributing

When making changes:

1. ✅ Test playbooks in check mode first (`--check`)
2. ✅ Ensure 1Password CLI is authenticated
3. ✅ Update this README with new variables or procedures
4. ✅ Test with verbose output (`-v`) to catch issues early
5. ✅ Follow existing role structure and naming conventions

---

**Built with ☕ for the FusionCloudX homelab!**
