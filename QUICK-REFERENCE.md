# PostgreSQL LXC Infrastructure - Quick Reference

⚡ Quick command reference for daily operations

## 🚀 Initial Deployment (Run Once)

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply

# 2. Set up Ansible
cd ../ansible
./setup-vault.sh
ansible-vault edit inventory/group_vars/vault.yml  # Update passwords

# 3. Update inventory and deploy
./update-inventory.sh
ansible postgresql -m ping
ansible-playbook playbooks/postgresql.yml
```

## 📋 Common Commands

### Terraform Operations

```bash
cd terraform

terraform plan                    # Preview changes
terraform apply                   # Apply changes
terraform destroy                 # Destroy infrastructure
terraform output                  # Show outputs
terraform output ansible_inventory_postgresql  # Show PostgreSQL inventory
```

### Ansible Operations

```bash
cd ansible

# Connectivity
ansible all -m ping                          # Test all hosts
ansible postgresql -m ping                   # Test PostgreSQL hosts

# Deployment
ansible-playbook playbooks/postgresql.yml    # Deploy all PostgreSQL
ansible-playbook playbooks/postgresql.yml --limit postgresql-semaphore  # Deploy one host
ansible-playbook playbooks/postgresql.yml --check  # Dry run

# Vault Operations
ansible-vault edit inventory/group_vars/vault.yml    # Edit passwords
ansible-vault view inventory/group_vars/vault.yml    # View passwords
ansible-vault encrypt inventory/group_vars/vault.yml # Encrypt file
ansible-vault decrypt inventory/group_vars/vault.yml # Decrypt file

# Inventory
./update-inventory.sh             # Update from Terraform (Linux/Mac)
.\update-inventory.ps1            # Update from Terraform (Windows)
ansible-inventory --list          # View parsed inventory
```

### PostgreSQL Management

```bash
# Service Control
ansible postgresql -m systemd -a "name=postgresql state=restarted" -b
ansible postgresql -m systemd -a "name=postgresql state=status" -b

# Database Operations
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c '\l'" -b  # List databases
ansible postgresql-semaphore -m shell -a "sudo -u postgres psql -c '\du'" -b # List users

# Logs
ansible postgresql -m shell -a "tail -50 /var/log/postgresql/postgresql-*.log" -b
ansible postgresql -m shell -a "journalctl -u postgresql -n 50" -b
```

## 🎯 Useful Tags

```bash
# Run specific parts of PostgreSQL role
ansible-playbook playbooks/postgresql.yml --tags install    # Only installation
ansible-playbook playbooks/postgresql.yml --tags config     # Only configuration
ansible-playbook playbooks/postgresql.yml --tags users      # Only user management
ansible-playbook playbooks/postgresql.yml --tags databases  # Only database creation
ansible-playbook playbooks/postgresql.yml --tags firewall   # Only firewall rules
ansible-playbook playbooks/postgresql.yml --tags verify     # Only verification
```

## 🔍 Verification

```bash
# Infrastructure
ssh terraform@zero.fusioncloudx.home
pct list | grep postgresql

# Connectivity
ansible postgresql -m ping

# PostgreSQL
ansible postgresql -m shell -a "psql --version" -b -u postgres
ansible postgresql -m shell -a "systemctl status postgresql" -b

# Database Access
ssh root@<postgresql-semaphore-ip>
sudo -u postgres psql
\l                    # List databases
\c semaphore          # Connect to database
\dt                   # List tables
\du                   # List users
\q                    # Quit
```

## 🐛 Quick Troubleshooting

```bash
# Can't connect to Proxmox?
ssh-add -l                                    # Check SSH keys
ssh terraform@zero.fusioncloudx.home          # Test connection

# Can't connect to containers?
./update-inventory.sh                         # Refresh inventory
ansible postgresql -m ping -vvv               # Verbose ping
ssh root@<container-ip>                       # Manual SSH test

# Vault errors?
ls -la .vault_pass                            # Check password file exists
ansible-vault view inventory/group_vars/vault.yml  # Test decryption

# PostgreSQL won't start?
ansible postgresql -m shell -a "journalctl -u postgresql -n 50" -b
ansible postgresql -m shell -a "df -h" -b     # Check disk space
```

## 📝 File Locations

```
terraform/
  ├── lxc-postgresql.tf      # LXC container definitions
  ├── variables.tf           # Configuration variables
  └── outputs.tf             # Terraform outputs

ansible/
  ├── ansible.cfg            # Ansible configuration
  ├── inventory/
  │   ├── hosts.ini         # Inventory (auto-updated)
  │   ├── group_vars/
  │   │   ├── postgresql.yml    # PostgreSQL config
  │   │   └── vault.yml         # Encrypted passwords
  │   └── host_vars/
  │       ├── postgresql-semaphore.yml  # Semaphore DB config
  │       └── postgresql-wazuh.yml      # Wazuh DB config
  ├── playbooks/
  │   └── postgresql.yml     # PostgreSQL playbook
  └── roles/postgresql/      # PostgreSQL role

POSTGRESQL-LXC-WORKFLOW.md   # Complete workflow guide
```

## 🔐 Security Reminders

- ✅ `.vault_pass` is in .gitignore - NEVER commit
- ✅ `vault.yml` should always be encrypted
- ✅ Back up your vault password securely
- ✅ Use strong passwords (32+ characters)
- ✅ Rotate passwords periodically

## 📊 Monitoring Snippets

```bash
# Database sizes
ansible postgresql -m shell -a "sudo -u postgres psql -c \"SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database;\"" -b

# Active connections
ansible postgresql -m shell -a "sudo -u postgres psql -c \"SELECT count(*) FROM pg_stat_activity;\"" -b

# Check for long-running queries
ansible postgresql -m shell -a "sudo -u postgres psql -c \"SELECT pid, now() - pg_stat_activity.query_start AS duration, query FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC;\"" -b
```

## 🎓 Help & Documentation

```bash
# Terraform help
terraform -help
terraform plan -help

# Ansible help
ansible --help
ansible-playbook --help
ansible-vault --help

# Full documentation
cat README.md                          # Main README
cat ansible/README.md                  # Ansible guide
cat POSTGRESQL-LXC-WORKFLOW.md         # Complete workflow
```

---

**Pro Tip**: Bookmark this file! It's your go-to reference for daily operations. ☕
