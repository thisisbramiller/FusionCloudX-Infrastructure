# 1Password Connect Migration Guide

This document explains the migration from `community.general.onepassword` (1Password CLI) to the official `onepassword.connect` collection.

## Why Migrate?

### Previous Implementation (community.general.onepassword)
- **Requires**: 1Password CLI (`op`) installed and signed in
- **Authentication**: Manual `eval $(op signin)` before each session
- **Architecture**: Direct CLI execution on localhost
- **Limitations**: Session expires, requires re-authentication

### New Implementation (onepassword.connect)
- **Official**: Maintained by 1Password, not community
- **Authentication**: Environment variables (persistent)
- **Architecture**: REST API via Connect Server or Service Account
- **Benefits**: No CLI required, better for automation, more secure

## Migration Steps

### 1. Install the Official Collection

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

This installs `onepassword.connect` version 2.3.1 or higher.

### 2. Choose Authentication Method

#### Option A: 1Password Service Account (Recommended for Simplicity)

1. Create a Service Account in 1Password:
   - Go to https://start.1password.com/integrations/infrastructure
   - Follow the wizard to create a Service Account
   - Grant access to "FusionCloudX Infrastructure" vault
   - Save the token (starts with `ops_`)

2. Set environment variable:

```bash
# Linux/macOS
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token_here"

# Add to ~/.bashrc or ~/.zshrc for persistence
echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"' >> ~/.bashrc

# Windows PowerShell
$env:OP_SERVICE_ACCOUNT_TOKEN = "ops_your_service_account_token_here"

# Add to PowerShell profile for persistence
Add-Content $PROFILE '$env:OP_SERVICE_ACCOUNT_TOKEN = "ops_your_token"'
```

#### Option B: 1Password Connect Server (Recommended for Homelab)

1. Deploy 1Password Connect Server:
   - Follow: https://developer.1password.com/docs/connect/get-started/
   - Docker deployment recommended for homelab

2. Set environment variables:

```bash
# Linux/macOS
export OP_CONNECT_HOST="http://your-connect-server:8080"
export OP_CONNECT_TOKEN="your-connect-token-here"

# Windows PowerShell
$env:OP_CONNECT_HOST = "http://your-connect-server:8080"
$env:OP_CONNECT_TOKEN = "your-connect-token-here"
```

### 3. Update Lookup Syntax

The collection has already been updated. Here are the changes made:

**Before:**
```yaml
postgresql_admin_password: "{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

**After:**
```yaml
postgresql_admin_password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

**Changed Files:**
- `ansible/inventory/host_vars/postgresql.yml` - 3 lookups updated
- `ansible/playbooks/postgresql.yml` - Pre-task checks updated
- `ansible/README.md` - Documentation updated
- `ansible/requirements.yml` - Created with collection dependency
- `ansible/ansible.cfg` - Added collections_paths

### 4. Verify Authentication

```bash
# Test that environment variables are set
echo $OP_SERVICE_ACCOUNT_TOKEN
# OR
echo $OP_CONNECT_HOST
echo $OP_CONNECT_TOKEN

# Test the lookup
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

Expected output: The password from 1Password (masked in actual use).

### 5. Test the Deployment

```bash
# Dry run to check what would change
ansible-playbook playbooks/postgresql.yml --check

# Run the actual deployment
ansible-playbook playbooks/postgresql.yml
```

## Troubleshooting

### Error: "Unable to locate collection"

```bash
# Reinstall the collection
ansible-galaxy collection install onepassword.connect --force

# Verify installation
ansible-galaxy collection list | grep onepassword
```

Expected output:
```
onepassword.connect    2.3.1
```

### Error: "Failed to retrieve item from 1Password"

Check authentication:

```bash
# For Service Account
echo $OP_SERVICE_ACCOUNT_TOKEN
# Should output: ops_...

# For Connect Server
echo $OP_CONNECT_HOST
# Should output: http://your-server:8080
echo $OP_CONNECT_TOKEN
# Should output: your-token

# Test connectivity (if using Connect Server)
curl -H "Authorization: Bearer $OP_CONNECT_TOKEN" $OP_CONNECT_HOST/health
# Should return: {"name":"1Password Connect API","version":"..."}
```

### Error: "Item not found"

Verify the 1Password item exists:

1. Log into 1Password web interface
2. Go to "FusionCloudX Infrastructure" vault
3. Verify these items exist:
   - "PostgreSQL Admin (postgres)"
   - "PostgreSQL - Semaphore DB User"
   - "PostgreSQL - Wazuh DB User"
4. Ensure each has a "password" field

### Permissions Issues (Service Account)

If using Service Account, ensure it has access to the vault:

1. Go to 1Password > Settings > Service Accounts
2. Click on your Service Account
3. Verify "FusionCloudX Infrastructure" vault is listed
4. Grant "Read" permissions if not already granted

## Comparison Table

| Feature | community.general.onepassword | onepassword.connect |
|---------|-------------------------------|---------------------|
| **Maintained by** | Community | 1Password (Official) |
| **Requires CLI** | Yes (`op`) | No |
| **Authentication** | `eval $(op signin)` | Environment variables |
| **Session expiry** | Yes (requires re-auth) | No (token-based) |
| **Architecture** | CLI execution | REST API |
| **Automation friendly** | Moderate | Excellent |
| **Homelab deployment** | Desktop app needed | Self-hosted Connect Server |
| **Security** | Session-based | Token-based |
| **Documentation** | Community docs | Official 1Password docs |

## Rollback Instructions

If you need to rollback (not recommended):

1. Install the old collection:
```bash
ansible-galaxy collection install community.general
```

2. Update lookups back to:
```yaml
lookup('community.general.onepassword', 'item', field='password', vault='vault-name')
```

3. Sign in to 1Password CLI:
```bash
eval $(op signin)
```

## Additional Resources

- [1Password Connect Documentation](https://developer.1password.com/docs/connect/)
- [Ansible Collection GitHub](https://github.com/1Password/ansible-onepasswordconnect-collection)
- [Collection Usage Guide](https://github.com/1Password/ansible-onepasswordconnect-collection/blob/main/USAGEGUIDE.md)
- [Service Accounts Documentation](https://developer.1password.com/docs/service-accounts/)
- [Connect Server Deployment Guide](https://developer.1password.com/docs/connect/get-started/)

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review 1Password Connect documentation
3. Check Ansible verbose output: `ansible-playbook -vvv`
4. Verify environment variables are set correctly

---

**Migration completed on**: 2025-12-12
**Tested on**: Homelab environment (semaphore-ui branch)
**Status**: Fully operational
