# 1Password Connect - Quick Start Guide

Quick reference for using the official 1Password Connect collection in Ansible.

## Authentication Setup (Choose One)

### Method 1: Service Account (Simplest)

```bash
# Set environment variable
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token"

# Make it persistent (Linux/macOS)
echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"' >> ~/.bashrc
source ~/.bashrc

# Make it persistent (Windows PowerShell)
Add-Content $PROFILE '$env:OP_SERVICE_ACCOUNT_TOKEN = "ops_your_token"'
. $PROFILE
```

### Method 2: Connect Server (For Homelab)

```bash
# Set environment variables
export OP_CONNECT_HOST="http://your-connect-server:8080"
export OP_CONNECT_TOKEN="your-connect-token"

# Make it persistent (Linux/macOS)
echo 'export OP_CONNECT_HOST="http://your-connect-server:8080"' >> ~/.bashrc
echo 'export OP_CONNECT_TOKEN="your-connect-token"' >> ~/.bashrc
source ~/.bashrc
```

## Installation

```bash
cd ansible

# Install the collection
ansible-galaxy collection install -r requirements.yml

# Verify installation
ansible-galaxy collection list | grep onepassword
```

Expected output: `onepassword.connect    2.3.1`

## Usage in Playbooks

### Basic Lookup

```yaml
- name: Example task with 1Password lookup
  debug:
    msg: "{{ lookup('onepassword.connect.generic_item', 'Item Name', field='password', vault='Vault Name') }}"
```

### In Variables

```yaml
# inventory/host_vars/hostname.yml
my_password: "{{ lookup('onepassword.connect.generic_item', 'Item Name', field='password', vault='Vault Name') }}"
my_username: "{{ lookup('onepassword.connect.generic_item', 'Item Name', field='username', vault='Vault Name') }}"
```

### With no_log (Security)

```yaml
- name: Set password securely
  set_fact:
    db_password: "{{ lookup('onepassword.connect.generic_item', 'DB Password', field='password', vault='Infrastructure') }}"
  no_log: true
```

## Testing

### Test Authentication

```bash
# Check environment variables
echo $OP_SERVICE_ACCOUNT_TOKEN
# OR
echo $OP_CONNECT_HOST
echo $OP_CONNECT_TOKEN

# Test Connect Server health (if using Connect Server)
curl -H "Authorization: Bearer $OP_CONNECT_TOKEN" $OP_CONNECT_HOST/health
```

### Test Ansible Lookup

```bash
# Test a lookup
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"

# Test with verbose output
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}" -vvv
```

## Common Lookup Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `field` | Field name to retrieve | `'password'`, `'username'`, `'url'` |
| `vault` | Vault name | `'FusionCloudX Infrastructure'` |
| `section` | Section within item (optional) | `'Database'` |

### Example with Multiple Fields

```yaml
vars:
  db_user: "{{ lookup('onepassword.connect.generic_item', 'Database Credentials', field='username', vault='Infrastructure') }}"
  db_pass: "{{ lookup('onepassword.connect.generic_item', 'Database Credentials', field='password', vault='Infrastructure') }}"
  db_host: "{{ lookup('onepassword.connect.generic_item', 'Database Credentials', field='server', vault='Infrastructure') }}"
  db_port: "{{ lookup('onepassword.connect.generic_item', 'Database Credentials', field='port', vault='Infrastructure') }}"
```

## Troubleshooting

### Collection Not Found

```bash
ansible-galaxy collection install onepassword.connect --force
```

### Authentication Failed

```bash
# Verify environment variables
env | grep OP_

# Expected output (one of):
# OP_SERVICE_ACCOUNT_TOKEN=ops_...
# OR
# OP_CONNECT_HOST=http://...
# OP_CONNECT_TOKEN=...
```

### Item Not Found

1. Verify item exists in 1Password web interface
2. Check exact item name (case-sensitive)
3. Verify vault name (case-sensitive)
4. Ensure Service Account has vault access

### Lookup Failing in Playbook

```bash
# Run with verbose output
ansible-playbook playbooks/your-playbook.yml -vvv

# Test the exact lookup on command line first
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'Your Item', field='password', vault='Your Vault') }}"
```

## Best Practices

### Security

1. **Never commit tokens**: Add to `.gitignore`
2. **Use no_log**: Prevent password logging
3. **Environment variables**: Store tokens in environment, not files
4. **Rotate tokens**: Periodically regenerate Service Account tokens

### Example with no_log

```yaml
- name: Configure database
  postgresql_user:
    name: "{{ db_user }}"
    password: "{{ db_password }}"  # Retrieved from 1Password
    state: present
  no_log: true  # Prevents password from appearing in logs
```

### Performance

1. **Cache lookups**: Lookups are performed each time - consider set_fact for reuse
2. **Minimize lookups**: Retrieve once and store as variable

```yaml
- name: Retrieve credentials once
  set_fact:
    cached_password: "{{ lookup('onepassword.connect.generic_item', 'Item', field='password', vault='Vault') }}"
  no_log: true

- name: Use cached value multiple times
  debug:
    msg: "Using password: {{ cached_password }}"
  no_log: true
```

## Common Patterns

### Database Configuration

```yaml
# host_vars/database.yml
postgresql_admin_password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin', field='password', vault='Infrastructure') }}"

postgresql_users:
  - name: "app1"
    password: "{{ lookup('onepassword.connect.generic_item', 'App1 DB User', field='password', vault='Infrastructure') }}"
  - name: "app2"
    password: "{{ lookup('onepassword.connect.generic_item', 'App2 DB User', field='password', vault='Infrastructure') }}"
```

### API Keys

```yaml
# host_vars/app.yml
api_keys:
  stripe: "{{ lookup('onepassword.connect.generic_item', 'Stripe API', field='secret key', vault='Infrastructure') }}"
  sendgrid: "{{ lookup('onepassword.connect.generic_item', 'SendGrid API', field='api key', vault='Infrastructure') }}"
  aws_access: "{{ lookup('onepassword.connect.generic_item', 'AWS Access', field='access key id', vault='Infrastructure') }}"
  aws_secret: "{{ lookup('onepassword.connect.generic_item', 'AWS Access', field='secret access key', vault='Infrastructure') }}"
```

### SSH Keys

```yaml
# Retrieve SSH private key
ssh_private_key: "{{ lookup('onepassword.connect.generic_item', 'Deployment SSH Key', field='private key', vault='Infrastructure') }}"
```

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `OP_SERVICE_ACCOUNT_TOKEN` | Yes* | Service Account token (starts with `ops_`) |
| `OP_CONNECT_HOST` | Yes** | Connect Server URL (e.g., `http://localhost:8080`) |
| `OP_CONNECT_TOKEN` | Yes** | Connect Server access token |

*Required if using Service Account method
**Required if using Connect Server method

## Quick Commands

```bash
# Install collection
ansible-galaxy collection install -r requirements.yml

# Test lookup
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'Item', field='password', vault='Vault') }}"

# List installed collections
ansible-galaxy collection list

# Check environment
env | grep OP_

# Run playbook with verbose output
ansible-playbook playbooks/site.yml -vvv
```

## Additional Resources

- **Official Docs**: https://developer.1password.com/docs/connect/ansible-collection
- **GitHub Repo**: https://github.com/1Password/ansible-onepasswordconnect-collection
- **Usage Guide**: https://github.com/1Password/ansible-onepasswordconnect-collection/blob/main/USAGEGUIDE.md
- **Service Accounts**: https://developer.1password.com/docs/service-accounts/

---

**Quick Start Version**: 1.0
**Last Updated**: 2025-12-12
**Tested With**: onepassword.connect 2.3.1+
