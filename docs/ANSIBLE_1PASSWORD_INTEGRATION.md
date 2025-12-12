# Ansible + 1Password Integration Guide

This guide explains how to use 1Password secrets in Ansible playbooks for the FusionCloudX Infrastructure project.

## Overview

Ansible retrieves secrets from 1Password at runtime using the `onepassword` lookup plugin from the `community.general` collection. Secrets are never stored in playbooks, variables files, or on disk.

## Architecture

```
┌────────────────────────────────────────────────────────┐
│              1Password (Homelab Vault)                 │
│  • PostgreSQL Admin (postgres) - password              │
│  • PostgreSQL - Semaphore Database User - password     │
│  • PostgreSQL - Wazuh Database User - password         │
└────────────────────────────────────────────────────────┘
                          ↑
                          │ 1Password CLI
                          │ (op command)
┌─────────────────────────┼──────────────────────────────┐
│         Ansible Playbook│(runtime secret retrieval)    │
│                         │                              │
│  - name: Set postgres password                         │
│    postgresql_user:                                    │
│      password: "{{ lookup('community.general.         │
│                    onepassword', 'PostgreSQL Admin',   │
│                    field='password') }}"               │
└────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **1Password CLI** installed and authenticated
2. **1Password account** with vault containing secrets
3. **Ansible** with `community.general` collection installed

## Installation

### Step 1: Install 1Password CLI

**macOS:**
```bash
brew install --cask 1password-cli
```

**Linux:**
```bash
# Download from https://1password.com/downloads/command-line/
curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli
```

**Windows:**
```powershell
# Using winget
winget install 1Password.CLI
```

### Step 2: Authenticate 1Password CLI

**Option A: Service Account (Recommended for Automation)**
```bash
# Export service account token
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

# Verify authentication
op vault list
```

**Option B: Interactive Login (For Development)**
```bash
# Sign in interactively
op signin

# You'll be prompted for your 1Password account
# Export the session for current shell
eval $(op signin)
```

**Option C: 1Password Connect**
```bash
# Export Connect server details
export OP_CONNECT_HOST="http://localhost:8080"
export OP_CONNECT_TOKEN="your-connect-token"

# Verify connection
op vault list
```

### Step 3: Install Ansible community.general Collection

```bash
ansible-galaxy collection install community.general
```

Verify installation:
```bash
ansible-galaxy collection list | grep community.general
# Should show: community.general X.X.X
```

## Usage in Ansible

### Basic Syntax

The `onepassword` lookup plugin syntax:

```yaml
{{ lookup('community.general.onepassword', 'Item Title', field='field_name', vault='Vault Name') }}
```

**Parameters:**
- `'Item Title'` - The title of the item in 1Password (required)
- `field='field_name'` - Specific field to retrieve (optional, defaults to 'password')
- `vault='Vault Name'` - Vault name or UUID (optional if you only have one vault)

### Common Field Names

- `password` - The password field (default)
- `username` - The username field
- `hostname` - The hostname field (for database items)
- `port` - The port field (for database items)
- `database` - The database name field (for database items)
- `notes` - The notes field
- Custom section fields: `section_name.field_label`

### Example: PostgreSQL Role Variables

Update `ansible/inventory/group_vars/postgresql.yml`:

```yaml
---
# ==============================================================================
# PostgreSQL Group Variables with 1Password Integration
# ==============================================================================

# PostgreSQL Version
postgresql_version: "15"

# PostgreSQL Global Configuration
postgresql_global_config:
  listen_addresses: "'*'"
  port: 5432
  max_connections: 100
  shared_buffers: "256MB"
  effective_cache_size: "1GB"
  # ... other config ...

# PostgreSQL Authentication (pg_hba.conf)
postgresql_hba_entries:
  - type: "local"
    database: "all"
    user: "all"
    method: "peer"
  - type: "host"
    database: "all"
    user: "all"
    address: "127.0.0.1/32"
    method: "scram-sha-256"
  - type: "host"
    database: "all"
    user: "all"
    address: "192.168.0.0/16"
    method: "scram-sha-256"

# Default Admin User
postgresql_admin_user: "postgres"

# Admin password retrieved from 1Password at runtime
postgresql_admin_password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"

# Packages to install
postgresql_packages:
  - "postgresql-{{ postgresql_version }}"
  - "postgresql-contrib-{{ postgresql_version }}"
  - "postgresql-client-{{ postgresql_version }}"
  - "python3-psycopg2"

# Service name
postgresql_service_name: "postgresql"

# Configuration files
postgresql_conf_path: "/etc/postgresql/{{ postgresql_version }}/main/postgresql.conf"
postgresql_hba_path: "/etc/postgresql/{{ postgresql_version }}/main/pg_hba.conf"

# ==============================================================================
# Databases Configuration - Single Instance, Multiple Databases
# ==============================================================================

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

# ==============================================================================
# Database Users Configuration
# ==============================================================================

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

# Firewall Rules
postgresql_firewall_rules:
  - rule: "allow"
    port: "5432"
    proto: "tcp"
    from_ip: "192.168.0.0/16"
    comment: "PostgreSQL access from local network"
```

### Example: Updated PostgreSQL Tasks

Update `ansible/roles/postgresql/tasks/main.yml` to use the new variable names:

```yaml
---
# ==============================================================================
# PostgreSQL Role - Main Tasks (1Password Integration)
# ==============================================================================

- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600
  tags: ['postgresql', 'install']

- name: Install PostgreSQL packages
  apt:
    name: "{{ postgresql_packages }}"
    state: present
  tags: ['postgresql', 'install']
  notify: restart postgresql

# ... [rest of tasks remain the same] ...

- name: Set PostgreSQL admin (postgres) user password
  postgresql_user:
    name: "{{ postgresql_admin_user }}"
    password: "{{ postgresql_admin_password }}"  # From 1Password
    encrypted: yes
  become: yes
  become_user: postgres
  when: postgresql_admin_password is defined
  tags: ['postgresql', 'users']
  no_log: true  # Don't log passwords

- name: Create PostgreSQL databases
  postgresql_db:
    name: "{{ item.name }}"
    owner: "{{ item.owner | default(omit) }}"
    encoding: "{{ item.encoding | default('UTF-8') }}"
    lc_collate: "{{ item.lc_collate | default('en_US.UTF-8') }}"
    lc_ctype: "{{ item.lc_ctype | default('en_US.UTF-8') }}"
    template: "{{ item.template | default('template0') }}"
    state: present
  become: yes
  become_user: postgres
  loop: "{{ postgresql_databases }}"
  when: postgresql_databases is defined and postgresql_databases | length > 0
  tags: ['postgresql', 'databases']

- name: Create PostgreSQL users
  postgresql_user:
    name: "{{ item.name }}"
    password: "{{ item.password }}"  # From 1Password
    db: "{{ item.database | default(omit) }}"
    priv: "{{ item.priv | default(omit) }}"
    role_attr_flags: "{{ item.role_attr_flags | default(omit) }}"
    encrypted: yes
    state: present
  become: yes
  become_user: postgres
  loop: "{{ postgresql_users }}"
  when: postgresql_users is defined and postgresql_users | length > 0
  tags: ['postgresql', 'users']
  no_log: true  # Don't log passwords

# ... [rest of tasks remain the same] ...
```

### Example: Inventory Configuration

Update `ansible/inventory/hosts.ini`:

```ini
# ==============================================================================
# Ansible Inventory - FusionCloudX Infrastructure
# ==============================================================================

# PostgreSQL Database Server (Single Instance)
[postgresql]
postgresql ansible_host=192.168.1.XXX

[postgresql:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# ==============================================================================
# Application Servers
# ==============================================================================

[application_servers]
semaphore-ui ansible_host=192.168.1.XXX

# ==============================================================================
# Meta Groups
# ==============================================================================

[homelab:children]
postgresql
application_servers

[homelab:vars]
ansible_connection=ssh
```

## Running Playbooks

### Method 1: Export Environment Variable (Recommended for Automation)

```bash
# Set service account token
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

# Run playbook
cd ansible/
ansible-playbook playbooks/postgresql.yml
```

### Method 2: Interactive 1Password Session

```bash
# Sign in to 1Password (interactive)
eval $(op signin)

# Run playbook
cd ansible/
ansible-playbook playbooks/postgresql.yml
```

### Method 3: 1Password Connect

```bash
# Set Connect environment variables
export OP_CONNECT_HOST="http://localhost:8080"
export OP_CONNECT_TOKEN="your-connect-token"

# Run playbook
cd ansible/
ansible-playbook playbooks/postgresql.yml
```

## Best Practices

### 1. Use no_log for Password Tasks

Always use `no_log: true` on tasks that handle passwords:

```yaml
- name: Set database password
  postgresql_user:
    name: myuser
    password: "{{ lookup('community.general.onepassword', 'My Item') }}"
  no_log: true  # Prevents password from appearing in logs
```

### 2. Set Default Vault

If you always use the same vault, set it as a default in `ansible.cfg`:

```ini
[community.general.onepassword]
vault = Homelab
```

Then you can omit `vault=` in lookups:
```yaml
password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password') }}"
```

### 3. Cache 1Password Session

For interactive use, cache the 1Password session:

```bash
# Sign in once, then export session
export OP_SESSION_myaccount=$(op signin myaccount --raw)

# Run multiple playbooks without re-authenticating
ansible-playbook playbook1.yml
ansible-playbook playbook2.yml
```

### 4. Use Descriptive Item Names

Make 1Password item names match their purpose:
- Good: `PostgreSQL - Semaphore Database User`
- Bad: `db_password_1`

This makes lookups more readable and maintainable.

### 5. Organize with Tags

Tag 1Password items for easy filtering:
- `terraform` - Created by Terraform
- `ansible` - Used by Ansible
- `postgresql` - Database credentials
- `homelab` - Homelab infrastructure

## Troubleshooting

### Error: "onepassword lookup plugin not found"

**Solution:**
```bash
ansible-galaxy collection install community.general
```

### Error: "401 Unauthorized" or "authentication failed"

**Solution:**
1. Check authentication:
   ```bash
   op vault list
   ```
2. Re-authenticate:
   ```bash
   eval $(op signin)
   ```
3. Verify service account token is valid

### Error: "Item not found"

**Solution:**
1. Verify item exists in 1Password:
   ```bash
   op item list --vault Homelab
   ```
2. Check item title matches exactly (case-sensitive)
3. Specify vault explicitly: `vault='Homelab'`

### Error: "Field not found"

**Solution:**
1. List item fields:
   ```bash
   op item get "PostgreSQL Admin (postgres)" --vault Homelab --format json
   ```
2. Use correct field name (usually lowercase: `password`, `username`, etc.)

### Playbook Hangs on 1Password Lookup

**Solution:**
1. Test 1Password CLI directly:
   ```bash
   op item get "PostgreSQL Admin (postgres)" --vault Homelab
   ```
2. Check environment variables are set:
   ```bash
   echo $OP_SERVICE_ACCOUNT_TOKEN
   echo $OP_SESSION_myaccount
   ```
3. Increase Ansible timeout if using Connect:
   ```yaml
   # In playbook or ansible.cfg
   timeout: 30
   ```

## Migration from ansible-vault

### Step-by-Step Migration

1. **Identify all vault variables:**
   ```bash
   # Find all vault_ prefixed variables
   grep -r "vault_" ansible/
   ```

2. **Create corresponding 1Password items** (already done by Terraform)

3. **Update variable references:**

   **Old (ansible-vault):**
   ```yaml
   password: "{{ vault_postgresql_admin_password }}"
   ```

   **New (1Password):**
   ```yaml
   password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"
   ```

4. **Test the migration:**
   ```bash
   # Dry run to verify lookups work
   ansible-playbook playbooks/postgresql.yml --check
   ```

5. **Remove vault files:**
   ```bash
   # After verifying everything works
   rm ansible/group_vars/vault.yml
   rm ansible/inventory/host_vars/postgresql-semaphore.yml  # Old host-specific vault file
   ```

### Variable Mapping

| Old Variable (ansible-vault) | New 1Password Item | Field |
|------------------------------|-------------------|-------|
| `vault_postgresql_admin_password` | `PostgreSQL Admin (postgres)` | `password` |
| `vault_semaphore_db_password` | `PostgreSQL - Semaphore Database User` | `password` |
| `vault_wazuh_db_password` | `PostgreSQL - Wazuh Database User` | `password` |

## Advanced Usage

### Using Custom Sections and Fields

If your 1Password item has custom sections:

```yaml
# Item structure:
# - Section: "Database"
#   - Field: "read_only_password"

readonly_password: "{{ lookup('community.general.onepassword', 'My Database', section='Database', field='read_only_password', vault='Homelab') }}"
```

### Retrieving Multiple Fields

```yaml
db_config:
  host: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='hostname', vault='Homelab') }}"
  port: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='port', vault='Homelab') }}"
  username: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='username', vault='Homelab') }}"
  password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}"
  database: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='database', vault='Homelab') }}"
```

### Using Environment Variables for Dynamic Lookups

```yaml
# Set item name via environment variable
- name: Get password
  set_fact:
    db_password: "{{ lookup('community.general.onepassword', lookup('env', 'DB_ITEM_NAME'), vault='Homelab') }}"
```

## Security Considerations

1. **Session Expiration** - 1Password CLI sessions expire after 30 minutes of inactivity
2. **Service Account Tokens** - Rotate tokens every 90 days
3. **Access Logging** - 1Password logs all secret access for audit trail
4. **No Caching** - Secrets are retrieved on-demand, never cached by Ansible
5. **TLS/HTTPS** - 1Password Connect uses TLS for all communication

## Next Steps

- Review the [1Password Lookup Plugin Documentation](https://docs.ansible.com/ansible/latest/collections/community/general/onepassword_lookup.html)
- Set up [1Password SSH Agent](https://developer.1password.com/docs/ssh/) for SSH key management
- Explore [1Password Secrets Automation](https://developer.1password.com/docs/ci-cd/) for CI/CD pipelines
- Consider implementing [Ansible Vault for Terraform State](https://www.terraform.io/docs/language/state/sensitive-data.html) encryption
