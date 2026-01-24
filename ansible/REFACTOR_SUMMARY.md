# 1Password Refactor Summary

## Overview

Successfully refactored Ansible configuration to use the **official 1Password Connect Ansible collection** (`onepassword.connect`) instead of the community collection (`community.general.onepassword`).

## Files Changed

### 1. Created Files

| File | Purpose |
|------|---------|
| `requirements.yml` | Defines Ansible collection dependencies (onepassword.connect >= 2.3.1) |
| `1PASSWORD_MIGRATION.md` | Comprehensive migration guide with troubleshooting |
| `ONEPASSWORD_QUICKSTART.md` | Quick reference for 1Password Connect usage |
| `REFACTOR_SUMMARY.md` | This file - summary of changes |

### 2. Modified Files

| File | Changes Made |
|------|--------------|
| `ansible.cfg` | Added `collections_paths` configuration |
| `inventory/host_vars/postgresql.yml` | Updated 3 lookups: admin password + 2 user passwords |
| `playbooks/postgresql.yml` | Updated pre-task checks for Connect authentication |
| `README.md` | Comprehensive documentation updates for official collection |

## Lookup Syntax Changes

### Before (community.general.onepassword)

```yaml
password: "{{ lookup('community.general.onepassword', 'Item Name', field='password', vault='Vault Name') }}"
```

### After (onepassword.connect)

```yaml
password: "{{ lookup('onepassword.connect.generic_item', 'Item Name', field='password', vault='Vault Name') }}"
```

## Authentication Changes

### Before: 1Password CLI

```bash
# Install CLI
brew install 1password-cli

# Sign in (expires after session)
eval $(op signin)
```

### After: 1Password Connect

```bash
# Option 1: Service Account (Simplest)
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"

# Option 2: Connect Server (Self-hosted)
export OP_CONNECT_HOST="http://connect-server:8080"
export OP_CONNECT_TOKEN="your-token"
```

## Updated Lookups

### postgresql.yml (host_vars)

1. **Line 50**: PostgreSQL admin password
   ```yaml
   postgresql_admin_password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
   ```

2. **Line 55**: Semaphore database user password
   ```yaml
   password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL - Semaphore DB User', field='password', vault='FusionCloudX Infrastructure') }}"
   ```

3. **Line 62**: Wazuh database user password
   ```yaml
   password: "{{ lookup('onepassword.connect.generic_item', 'PostgreSQL - Wazuh DB User', field='password', vault='FusionCloudX Infrastructure') }}"
   ```

## Installation Steps

### 1. Install Collection

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

### 2. Setup Authentication

Choose one method:

**Service Account (Recommended):**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token"
```

**Connect Server:**
```bash
export OP_CONNECT_HOST="http://your-connect-server:8080"
export OP_CONNECT_TOKEN="your-connect-token"
```

### 3. Test

```bash
# Verify collection
ansible-galaxy collection list | grep onepassword

# Test lookup
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"

# Run playbook
ansible-playbook playbooks/postgresql.yml --check
```

## Benefits of This Refactor

### 1. Official Support
- Maintained by 1Password, not community
- Better documentation and support
- Regular updates and bug fixes

### 2. No CLI Required
- No need to install 1Password CLI
- No `op signin` sessions to manage
- Better for automation and CI/CD

### 3. Persistent Authentication
- Environment variables don't expire
- No need to re-authenticate each session
- Better for long-running processes

### 4. Self-Hosted Option
- Can deploy Connect Server in homelab
- No external dependencies for secret retrieval
- Better control over secret access

### 5. Better Security
- Token-based authentication
- Fine-grained permissions via Service Accounts
- Audit logs for secret access

## Verification Checklist

- [x] Created `requirements.yml` with collection dependency
- [x] Updated `ansible.cfg` with collections_paths
- [x] Updated all 3 lookups in `inventory/host_vars/postgresql.yml`
- [x] Updated pre-task checks in `playbooks/postgresql.yml`
- [x] Updated `README.md` with new instructions
- [x] Created migration guide (`1PASSWORD_MIGRATION.md`)
- [x] Created quick start guide (`ONEPASSWORD_QUICKSTART.md`)
- [x] All syntax using `onepassword.connect.generic_item`
- [x] No references to `community.general.onepassword` in active code

## Testing Plan

### 1. Collection Installation

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-galaxy collection list | grep onepassword
```

Expected: `onepassword.connect    2.3.1` (or higher)

### 2. Authentication Setup

```bash
# Set environment variable (choose one method)
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token"
# Verify
echo $OP_SERVICE_ACCOUNT_TOKEN
```

### 3. Lookup Test

```bash
ansible localhost -m debug -a "msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}"
```

Expected: Password retrieved successfully

### 4. Playbook Check

```bash
ansible-playbook playbooks/postgresql.yml --check
```

Expected: No errors, shows planned changes

### 5. Full Deployment

```bash
ansible-playbook playbooks/postgresql.yml
```

Expected: Successful deployment with credentials from 1Password

## Troubleshooting

### Issue: Collection not found

**Solution:**
```bash
ansible-galaxy collection install onepassword.connect --force
```

### Issue: Authentication failed

**Solution:**
```bash
# Verify environment variables
env | grep OP_
# Should show: OP_SERVICE_ACCOUNT_TOKEN or OP_CONNECT_HOST+TOKEN
```

### Issue: Item not found

**Solution:**
1. Check item exists in 1Password web interface
2. Verify exact item name (case-sensitive)
3. Verify vault name (case-sensitive)
4. Ensure Service Account has vault access

## Rollback Plan

If issues arise, rollback steps:

1. Reinstall community collection:
   ```bash
   ansible-galaxy collection install community.general
   ```

2. Revert lookups to:
   ```yaml
   lookup('community.general.onepassword', 'item', field='field', vault='vault')
   ```

3. Sign in with CLI:
   ```bash
   eval $(op signin)
   ```

**Note:** Not recommended - official collection is superior.

## Documentation References

| Document | Purpose |
|----------|---------|
| `README.md` | Main documentation with updated 1Password instructions |
| `1PASSWORD_MIGRATION.md` | Detailed migration guide from old to new collection |
| `ONEPASSWORD_QUICKSTART.md` | Quick reference for day-to-day usage |
| `requirements.yml` | Collection dependencies |

## External Resources

- [1Password Connect Docs](https://developer.1password.com/docs/connect/ansible-collection)
- [Collection GitHub](https://github.com/1Password/ansible-onepasswordconnect-collection)
- [Usage Guide](https://github.com/1Password/ansible-onepasswordconnect-collection/blob/main/USAGEGUIDE.md)
- [Service Accounts](https://developer.1password.com/docs/service-accounts/)

## Status

- **Branch**: semaphore-ui
- **Date**: 2025-12-12
- **Status**: ✅ Complete
- **Tested**: Pending (awaiting user test)
- **Environment**: Homelab/Development

## Next Steps

1. User to setup 1Password authentication (Service Account or Connect Server)
2. Install collection: `ansible-galaxy collection install -r requirements.yml`
3. Test lookups with verbose output
4. Run PostgreSQL playbook in check mode
5. Deploy to production (if tests pass)

---

**Refactor completed by**: Claude Code
**Review status**: Ready for testing
**Breaking changes**: Yes - requires environment variable setup
