# 1Password Setup Guide

This guide explains how to set up 1Password for secrets management in the FusionCloudX Infrastructure project.

## Overview

The infrastructure uses 1Password to securely manage sensitive credentials like database passwords, API keys, and SSH keys. This replaces ansible-vault and provides:

- **Centralized secrets management** - One source of truth for all credentials
- **Automatic password generation** - Terraform generates strong passwords automatically
- **Easy rotation** - Update secrets in one place, deploy everywhere
- **Audit trail** - 1Password tracks who accessed what and when
- **Team sharing** - Share credentials securely with team members

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     1Password Account                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Homelab Vault                             │ │
│  │  • PostgreSQL Admin (postgres)                         │ │
│  │  • PostgreSQL - Semaphore Database User                │ │
│  │  • PostgreSQL - Wazuh Database User                    │ │
│  │  • [Future: SSH Keys, API Tokens, etc.]               │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                          ↑ ↑
                          │ │
           ┌──────────────┘ └──────────────┐
           │                                │
   ┌───────▼──────────┐          ┌────────▼──────────┐
   │    Terraform     │          │      Ansible      │
   │  (creates items) │          │ (reads secrets)   │
   └──────────────────┘          └───────────────────┘
```

## Prerequisites

1. **1Password Account** - Personal, Family, or Teams account
2. **1Password CLI** - Install from https://1password.com/downloads/command-line/

## Setup Options

There are two ways to authenticate Terraform and Ansible with 1Password:

### Option 1: Service Account (Recommended for Homelab)

Service accounts provide token-based authentication without requiring the 1Password app.

**Pros:**
- Simpler setup
- No need to run 1Password Connect server
- Perfect for homelab environments
- Works directly from command line

**Cons:**
- Requires 1Password Business or Teams (not available on Personal/Family plans)
- Limited to 1Password cloud (no self-hosted option)

### Option 2: 1Password Connect (Advanced)

1Password Connect is a self-hosted server that provides API access to your vaults.

**Pros:**
- Works with any 1Password plan (including Personal/Family)
- Self-hosted - runs in your homelab
- More control over access patterns
- Scalable for larger teams

**Cons:**
- More complex setup
- Requires running additional service (Connect server)
- Need to manage Connect credentials

## Option 1: Service Account Setup

### Step 1: Create Service Account

1. Sign in to 1Password at https://my.1password.com/
2. Go to **Settings** > **Service Accounts**
3. Click **Create Service Account**
4. Name it: `terraform-homelab`
5. Grant access to the vault(s) you want to use (e.g., "Homelab")
6. Copy the service account token (starts with `ops_`) - **you only see this once!**

### Step 2: Create Vault and Get Vault ID

1. In 1Password, create a vault named "Homelab" (or use existing vault)
2. Get the vault UUID:
   ```bash
   # Set service account token
   export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

   # List vaults to find the UUID
   op vault list
   ```
3. Copy the UUID for your "Homelab" vault (e.g., `abcd1234efgh5678ijkl9012mnop3456`)

### Step 3: Configure Terraform

1. Create `terraform/terraform.tfvars` file:
   ```hcl
   # 1Password Configuration
   onepassword_vault_id = "your-vault-uuid-here"
   ```

2. Export the service account token as environment variable:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc for persistence
   export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"
   ```

3. Verify the setup:
   ```bash
   cd terraform/
   terraform init
   terraform plan
   ```

## Option 2: 1Password Connect Setup

### Step 1: Create Connect Token

1. Sign in to 1Password at https://my.1password.com/
2. Go to **Developer** > **Infrastructure Secrets** > **Connect**
3. Click **Set Up Connect Server**
4. Create a new server: `homelab-connect`
5. Grant access to your "Homelab" vault
6. Download the `1password-credentials.json` file
7. Copy the Connect token (starts with `ey`)

### Step 2: Deploy 1Password Connect Server

You can deploy Connect as a Docker container or on Kubernetes. For homelab, Docker is simpler.

#### Docker Deployment

1. Create directory for Connect:
   ```bash
   mkdir -p ~/1password-connect
   cd ~/1password-connect
   ```

2. Copy the credentials file:
   ```bash
   cp ~/Downloads/1password-credentials.json ./
   ```

3. Create `docker-compose.yml`:
   ```yaml
   version: '3.8'

   services:
     connect-api:
       image: 1password/connect-api:latest
       container_name: onepassword-connect-api
       hostname: connect-api
       ports:
         - "8080:8080"
       volumes:
         - ./1password-credentials.json:/home/opuser/.op/1password-credentials.json:ro
         - connect-data:/home/opuser/.op/data
       environment:
         - OP_SESSION=/home/opuser/.op/data
       restart: unless-stopped

     connect-sync:
       image: 1password/connect-sync:latest
       container_name: onepassword-connect-sync
       hostname: connect-sync
       volumes:
         - ./1password-credentials.json:/home/opuser/.op/1password-credentials.json:ro
         - connect-data:/home/opuser/.op/data
       environment:
         - OP_SESSION=/home/opuser/.op/data
         - OP_HTTP_PORT=8081
       restart: unless-stopped

   volumes:
     connect-data:
   ```

4. Start Connect:
   ```bash
   docker-compose up -d
   ```

5. Verify Connect is running:
   ```bash
   curl http://localhost:8080/health
   # Should return: {"name":"1Password Connect API","version":"X.X.X"}
   ```

### Step 3: Configure Terraform for Connect

1. Create `terraform/terraform.tfvars`:
   ```hcl
   # 1Password Configuration
   onepassword_vault_id = "your-vault-uuid-here"
   ```

2. Export Connect environment variables:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc for persistence
   export OP_CONNECT_HOST="http://localhost:8080"
   export OP_CONNECT_TOKEN="your-connect-token-here"
   ```

3. Verify the setup:
   ```bash
   cd terraform/
   terraform init
   terraform plan
   ```

## Terraform Usage

Once configured, Terraform will automatically:

1. **Create password items** in 1Password when you run `terraform apply`
2. **Generate strong passwords** using the password recipes defined in `lxc-postgresql.tf`
3. **Store metadata** like hostname, port, database name alongside the password

Example workflow:
```bash
cd terraform/

# Initialize Terraform (first time only)
terraform init

# Preview what will be created
terraform plan

# Create infrastructure and 1Password items
terraform apply

# View the created 1Password item IDs
terraform output onepassword_postgresql_admin_id
terraform output onepassword_semaphore_db_id
```

## Ansible Usage

See [ANSIBLE_1PASSWORD_INTEGRATION.md](./ANSIBLE_1PASSWORD_INTEGRATION.md) for detailed instructions on using 1Password with Ansible.

**Quick overview:**
- Ansible will use the **1Password CLI** to retrieve secrets
- Use `lookup` plugin: `{{ lookup('community.general.onepassword', 'PostgreSQL Admin (postgres)', field='password', vault='Homelab') }}`
- Secrets are never stored in playbooks or variables files

## Security Best Practices

1. **Never commit tokens** - Add `terraform.tfvars` and `.env` to `.gitignore`
2. **Rotate tokens regularly** - Update service account tokens every 90 days
3. **Use separate vaults** - Separate vaults for dev/staging/production
4. **Audit access** - Review 1Password audit logs monthly
5. **Limit service account access** - Only grant access to vaults that are needed
6. **Use Connect for production** - Service accounts are good for homelab, Connect is better for production

## Troubleshooting

### Terraform Can't Authenticate with 1Password

**Error:** `Error: authentication failed: unable to authenticate`

**Solution:**
1. Verify environment variable is set: `echo $OP_SERVICE_ACCOUNT_TOKEN` or `echo $OP_CONNECT_TOKEN`
2. Check token hasn't expired
3. Ensure token has correct format (starts with `ops_` for service account or `ey` for Connect)

### Vault UUID Not Found

**Error:** `Error: vault not found`

**Solution:**
1. List vaults: `op vault list`
2. Verify vault UUID is correct in `terraform.tfvars`
3. Ensure service account/Connect token has access to the vault

### 1Password Connect Not Responding

**Solution:**
1. Check Connect is running: `docker ps | grep connect`
2. Check logs: `docker-compose logs connect-api`
3. Verify health endpoint: `curl http://localhost:8080/health`
4. Restart Connect: `docker-compose restart`

## Migration from ansible-vault

To migrate existing secrets from ansible-vault to 1Password:

1. **Decrypt existing vault file:**
   ```bash
   ansible-vault decrypt ansible/group_vars/vault.yml
   ```

2. **Manually create items in 1Password** using the web interface or CLI for each secret

3. **Verify Terraform creates the correct items:**
   ```bash
   terraform apply
   ```

4. **Update Ansible playbooks** to use 1Password lookup plugin (see ANSIBLE_1PASSWORD_INTEGRATION.md)

5. **Delete old vault file** once migration is verified:
   ```bash
   rm ansible/group_vars/vault.yml
   ```

## Next Steps

- See [ANSIBLE_1PASSWORD_INTEGRATION.md](./ANSIBLE_1PASSWORD_INTEGRATION.md) for Ansible integration
- Review [Terraform 1Password Provider Docs](https://registry.terraform.io/providers/1Password/onepassword/latest/docs)
- Set up 1Password browser extension for easy access to credentials
- Configure 1Password SSH agent for SSH key management
