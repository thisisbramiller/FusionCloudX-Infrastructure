# Ansible Configuration for FusionCloudX Infrastructure

This directory contains Ansible automation for configuring and managing FusionCloudX infrastructure. It follows industry best practices with proper separation of concerns, secure secret management, and idempotent playbooks.

## 📁 Directory Structure

```
ansible/
├── ansible.cfg                 # Ansible configuration
├── inventory/
│   ├── hosts.ini              # Inventory file (auto-updated from Terraform)
│   ├── group_vars/
│   │   ├── all.yml           # Global variables for all hosts
│   │   ├── postgresql.yml    # PostgreSQL group variables
│   │   └── vault.yml         # Encrypted secrets (ansible-vault)
│   └── host_vars/
│       ├── postgresql-semaphore.yml   # Semaphore DB host variables
│       └── postgresql-wazuh.yml       # Wazuh DB host variables
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
├── setup-vault.sh             # Script to initialize ansible-vault
└── .vault_pass                # Vault password (DO NOT COMMIT!)
```

## 🚀 Quick Start

### 1. Initial Setup

First, set up ansible-vault for secure password management:

```bash
# Run the vault setup script
cd ansible
./setup-vault.sh

# Or manually create vault password
echo "your-secure-password" > .vault_pass
chmod 600 .vault_pass

# Encrypt the vault file
ansible-vault encrypt inventory/group_vars/vault.yml
```

### 2. Update Passwords

Edit the encrypted vault file to set your actual passwords:

```bash
# Edit vault file (opens in your default editor)
ansible-vault edit inventory/group_vars/vault.yml

# Update these passwords:
# - vault_postgresql_admin_password
# - vault_semaphore_db_password
# - vault_wazuh_db_password
```

### 3. Update Inventory from Terraform

After deploying LXC containers with Terraform, update the Ansible inventory:

```bash
# On Linux/Mac/WSL
./update-inventory.sh

# On Windows PowerShell
.\update-inventory.ps1
```

This script extracts container IP addresses from Terraform outputs and updates `inventory/hosts.ini`.

### 4. Test Connectivity

Verify Ansible can connect to all PostgreSQL hosts:

```bash
# Ping all hosts
ansible all -m ping

# Ping just PostgreSQL hosts
ansible postgresql -m ping
```

### 5. Deploy PostgreSQL

Run the PostgreSQL deployment playbook:

```bash
# Deploy to all PostgreSQL hosts
ansible-playbook playbooks/postgresql.yml

# Deploy to a specific host
ansible-playbook playbooks/postgresql.yml --limit postgresql-semaphore

# Run with verbose output
ansible-playbook playbooks/postgresql.yml -v

# Check what would change (dry run)
ansible-playbook playbooks/postgresql.yml --check
```

## 🔐 Security & Best Practices

### Vault Management

**Encrypting Files:**
```bash
ansible-vault encrypt inventory/group_vars/vault.yml
```

**Editing Encrypted Files:**
```bash
ansible-vault edit inventory/group_vars/vault.yml
```

**Viewing Encrypted Files:**
```bash
ansible-vault view inventory/group_vars/vault.yml
```

**Changing Vault Password:**
```bash
ansible-vault rekey inventory/group_vars/vault.yml
```

### Important Security Notes

- ✅ `.vault_pass` is in `.gitignore` - NEVER commit this file
- ✅ `vault.yml` should always be encrypted before committing
- ✅ All database passwords are stored in encrypted vault
- ✅ Vault password is required to run playbooks (configured in `ansible.cfg`)
- ✅ Back up your vault password securely!

## 📊 PostgreSQL Role

The PostgreSQL role handles complete database server setup:

### What it Does

1. **Installation**: Installs PostgreSQL 15 and required packages
2. **Configuration**: Applies optimized settings from templates
3. **Authentication**: Configures `pg_hba.conf` for secure access
4. **Database Creation**: Creates application databases
5. **User Management**: Creates database users with proper privileges
6. **Firewall**: Configures UFW rules for PostgreSQL access
7. **Verification**: Validates the deployment

### Configuration

PostgreSQL configuration is split across multiple files:

- **Group Vars** (`inventory/group_vars/postgresql.yml`): Shared configuration for all PostgreSQL servers
- **Host Vars** (`inventory/host_vars/postgresql-*.yml`): Host-specific tuning and database definitions
- **Vault** (`inventory/group_vars/vault.yml`): Encrypted passwords

### Per-Host Configuration

Each PostgreSQL instance has its own configuration file in `inventory/host_vars/`:

**postgresql-semaphore.yml:**
- Memory: 2GB RAM → 512MB shared_buffers, 1.5GB effective_cache_size
- Database: `semaphore` owned by user `semaphore`
- Backup retention: 7 days

**postgresql-wazuh.yml:**
- Memory: 4GB RAM → 1GB shared_buffers, 3GB effective_cache_size
- Database: `wazuh` owned by user `wazuh`
- Max connections: 200 (higher for SIEM workload)
- Backup retention: 30 days

## 🎯 Common Tasks

### Deploy Single Host

```bash
ansible-playbook playbooks/postgresql.yml --limit postgresql-semaphore
```

### Run Specific Tags

```bash
# Only install packages
ansible-playbook playbooks/postgresql.yml --tags install

# Only configure (skip installation)
ansible-playbook playbooks/postgresql.yml --tags config

# Only manage users and databases
ansible-playbook playbooks/postgresql.yml --tags users,databases
```

### Ad-hoc Commands

```bash
# Check PostgreSQL version
ansible postgresql -a "psql --version" -b -u postgres

# Check PostgreSQL service status
ansible postgresql -m systemd -a "name=postgresql state=started" -b

# Restart PostgreSQL on all hosts
ansible postgresql -m systemd -a "name=postgresql state=restarted" -b
```

### Verify Deployment

```bash
# Run the verification tasks
ansible-playbook playbooks/postgresql.yml --tags verify

# Connect to database (from a PostgreSQL host)
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c '\l'" -b
```

## 🔄 Workflow: Terraform → Ansible

This is the recommended workflow for infrastructure deployment:

```bash
# 1. Provision LXC containers with Terraform
cd terraform
terraform init
terraform plan
terraform apply

# 2. Update Ansible inventory from Terraform outputs
cd ../ansible
./update-inventory.sh  # or update-inventory.ps1 on Windows

# 3. Test connectivity
ansible postgresql -m ping

# 4. Deploy PostgreSQL
ansible-playbook playbooks/postgresql.yml

# 5. Verify deployment
ansible-playbook playbooks/postgresql.yml --tags verify
```

## 🛠️ Customization

### Adding a New PostgreSQL Instance

1. **Update Terraform** (`terraform/variables.tf`):
   ```hcl
   "postgresql-newservice" = {
     vm_id       = 2003
     hostname    = "postgresql-newservice"
     memory_mb   = 2048
     cpu_cores   = 2
     disk_gb     = 32
     started     = true
   }
   ```

2. **Create Host Vars** (`ansible/inventory/host_vars/postgresql-newservice.yml`):
   ```yaml
   postgresql_databases:
     - name: "newservice"
       owner: "newservice"

   postgresql_users:
     - name: "newservice"
       password: "{{ vault_newservice_db_password }}"
       database: "newservice"
   ```

3. **Add Password to Vault**:
   ```bash
   ansible-vault edit inventory/group_vars/vault.yml
   # Add: vault_newservice_db_password: "secure_password_here"
   ```

4. **Deploy**:
   ```bash
   cd terraform && terraform apply
   cd ../ansible && ./update-inventory.sh
   ansible-playbook playbooks/postgresql.yml --limit postgresql-newservice
   ```

### Tuning PostgreSQL

Edit `inventory/group_vars/postgresql.yml` for global settings or `inventory/host_vars/postgresql-*.yml` for per-host tuning:

```yaml
postgresql_instance_config:
  shared_buffers: "512MB"
  effective_cache_size: "1536MB"
  work_mem: "8MB"
  max_connections: 150
```

## 📝 Variables Reference

### Global Variables (all.yml)

- `timezone`: System timezone (default: America/Chicago)
- `dns_nameservers`: DNS servers
- `firewall_enabled`: Enable UFW firewall

### PostgreSQL Group Variables (postgresql.yml)

- `postgresql_version`: PostgreSQL version (default: 15)
- `postgresql_global_config`: Configuration applied to all instances
- `postgresql_hba_entries`: Authentication rules (pg_hba.conf)
- `postgresql_packages`: Packages to install

### Host Variables (host_vars/*.yml)

- `postgresql_instance_config`: Override global config for this host
- `postgresql_databases`: Databases to create
- `postgresql_users`: Users to create
- `postgresql_firewall_rules`: UFW rules for this host

### Vault Variables (vault.yml - encrypted)

- `vault_postgresql_admin_password`: postgres superuser password
- `vault_semaphore_db_password`: semaphore database user password
- `vault_wazuh_db_password`: wazuh database user password

## 🐛 Troubleshooting

### Vault password errors

```bash
# Verify vault password file exists
ls -la .vault_pass

# Verify vault file can be decrypted
ansible-vault view inventory/group_vars/vault.yml
```

### Connection issues

```bash
# Test SSH connectivity
ansible postgresql -m ping -vvv

# Check inventory
ansible-inventory --list

# Verify SSH key is loaded
ssh root@<container-ip>
```

### PostgreSQL role failures

```bash
# Run with verbose output
ansible-playbook playbooks/postgresql.yml -vvv

# Check PostgreSQL logs on the host
ansible postgresql-semaphore -m shell -a "tail -50 /var/log/postgresql/postgresql-*.log" -b
```

### Inventory not updating

```bash
# Manually check Terraform outputs
cd terraform
terraform output ansible_inventory_postgresql

# Verify jq is installed (required for update-inventory.sh)
which jq
```

## 📚 Additional Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

## 🤝 Contributing

When making changes:

1. ✅ Test playbooks in a development environment first
2. ✅ Use `--check` mode before applying changes
3. ✅ Keep vault.yml encrypted
4. ✅ Document new variables in this README
5. ✅ Follow existing role structure and naming conventions

---

**Built with ☕ for the FusionCloudX homelab by NetworkChuck energy!**
