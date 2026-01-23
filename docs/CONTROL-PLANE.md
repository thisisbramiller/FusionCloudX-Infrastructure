# Semaphore Control Plane Architecture

This document describes the Infrastructure Control Plane architecture using Semaphore UI as the central automation hub.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Bootstrap Process](#bootstrap-process)
4. [SSH Key Management](#ssh-key-management)
5. [Repository Management](#repository-management)
6. [1Password Integration](#1password-integration)
7. [Semaphore Configuration](#semaphore-configuration)
8. [Day-to-Day Workflow](#day-to-day-workflow)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The Semaphore Control Plane transforms the `semaphore-ui` VM into a centralized hub for all infrastructure automation. Instead of running Terraform and Ansible from your workstation, everything runs from Semaphore UI through a web interface.

### Why This Approach?

**Benefits:**
- **Single Source of Truth**: All automation runs from one place
- **Audit Trail**: Complete history of who ran what and when
- **Team Collaboration**: Multiple people can use the same control plane
- **Scheduled Automation**: Run playbooks on a schedule
- **Web-Based**: No local Terraform/Ansible installation needed
- **Secure Secrets**: 1Password integration for sensitive data
- **Consistent Environment**: Same execution environment every time

**Use Cases:**
- Deploy infrastructure changes from the office or remotely
- Schedule nightly backups or updates
- Allow team members to run playbooks without CLI access
- Maintain consistent execution environment
- Audit all infrastructure changes

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR WORKSTATION                         │
│  • Access Semaphore UI (https://semaphore.home)                 │
│  • Git push/pull (development)                                  │
│  • Bootstrap only (one-time setup)                              │
└────────────────┬───────────────────────────────────────────────┘
                 │
                 │ HTTPS (Semaphore Web UI)
                 │
┌────────────────▼───────────────────────────────────────────────┐
│          SEMAPHORE-UI VM (Control Plane)                       │
│                    VM ID 1102                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ /opt/infrastructure/ (Git Repository)                   │  │
│  │  ├── terraform/      (Proxmox infrastructure)           │  │
│  │  ├── ansible/        (Configuration management)         │  │
│  │  └── scripts/        (Helper scripts)                   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ Installed Components:                                   │  │
│  │  • Semaphore UI      → Web interface for automation     │  │
│  │  • Ansible 2.18+     → Configuration management         │  │
│  │  • Terraform 1.10+   → Infrastructure as code           │  │
│  │  • 1Password CLI     → Secrets management               │  │
│  │  • Git               → Version control                  │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ SSH Keys (as ansible user):                             │  │
│  │  • ~/.ssh/id_ed25519         → Managed hosts            │  │
│  │  • ~/.ssh/github_deploy_key  → GitHub repository        │  │
│  │  • ~/.ssh/proxmox_terraform_key → Proxmox access        │  │
│  └─────────────────────────────────────────────────────────┘  │
└──────────────────┬─────────────────┬────────────────────────────┘
                   │                 │
                   │ PostgreSQL      │ SSH/API
                   │ (TCP 5432)      │ (Ansible/Terraform)
                   │                 │
         ┌─────────▼─────────┐  ┌───▼──────────────────────────┐
         │ PostgreSQL LXC    │  │  MANAGED INFRASTRUCTURE      │
         │   (VM ID 2001)    │  │   • Proxmox VMs & LXCs       │
         │                   │  │   • Network devices          │
         │ • semaphore DB    │  │   • Services & applications  │
         │ • wazuh DB        │  └──────────────────────────────┘
         └───────────────────┘
```

### Data Flow

1. **User** accesses Semaphore UI in web browser
2. **Semaphore** pulls latest code from GitHub repository
3. **Semaphore** executes Ansible/Terraform from `/opt/infrastructure`
4. **Ansible/Terraform** connects to infrastructure using SSH keys
5. **1Password CLI** retrieves secrets during execution
6. **Results** displayed in Semaphore UI with logs and history

---

## Bootstrap Process

Bootstrap is a **ONE-TIME** setup that transforms semaphore-ui into the control plane. After bootstrap, all automation runs through Semaphore.

### Three-Phase Bootstrap

#### Phase 1: Cloud-Init (Automatic)

Cloud-init runs during VM provisioning and installs:
- Base system packages (git, curl, python3, etc.)
- Ansible via pip
- Build tools for Ansible modules
- Directory structure (`/opt/infrastructure`)
- SSH configuration templates
- Environment variable placeholders

**Status**: ✓ Configured in `terraform/cloud-init.tf`

#### Phase 2: Workstation Bootstrap (One-Time Manual)

Run Ansible from YOUR workstation to configure semaphore-ui:

```bash
# Quick start (guided script)
./scripts/bootstrap-control-plane.sh

# Manual approach
ansible-playbook \
  -i 'SEMAPHORE_IP,' \
  -u ansible \
  ansible/playbooks/bootstrap-semaphore.yml \
  -e "onepassword_service_account_token=YOUR_TOKEN"
```

This configures:
- Terraform installation
- 1Password CLI installation
- SSH key generation (3 keys)
- Infrastructure repository clone
- Ansible collections installation
- Semaphore UI installation and configuration
- Environment variables
- Systemd service

**Duration**: 5-10 minutes

#### Phase 3: Self-Management (Ongoing)

After bootstrap, semaphore-ui manages itself:
- All playbooks run through Semaphore UI
- Infrastructure changes via Semaphore
- Git updates pulled manually or via webhook
- No workstation Ansible needed

### Bootstrap Walkthrough

**Step 1: Provision Infrastructure**

```bash
cd terraform/
terraform apply
```

Wait for `semaphore-ui` VM to finish cloud-init (check `/var/lib/cloud-init.semaphore.ready`).

**Step 2: Get VM IP Address**

```bash
terraform output vm_ipv4_addresses
```

**Step 3: Test SSH Access**

```bash
ssh ansible@SEMAPHORE_IP
# Should connect successfully with your GitHub SSH key
exit
```

**Step 4: Run Bootstrap**

```bash
cd ..  # Back to project root
./scripts/bootstrap-control-plane.sh
```

Follow the prompts to provide:
- Semaphore IP address
- 1Password service account token
- Database password (optional)

**Step 5: Configure GitHub Deploy Key**

```bash
# Get the public key
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/github_deploy_key.pub'

# Add to GitHub:
# Repository → Settings → Deploy keys → Add deploy key
# ✓ Allow write access (if you want to push from Semaphore)
```

**Step 6: Configure Proxmox SSH Access**

```bash
# Get the public key
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/proxmox_terraform_key.pub'

# Add to Proxmox
ssh root@192.168.40.206
mkdir -p /root/.ssh
echo 'PUBLIC_KEY' >> /root/.ssh/authorized_keys
```

**Step 7: Complete Semaphore Initial Setup**

1. Open `http://SEMAPHORE_IP:3000`
2. Create first admin user
3. Add repository:
   - URL: `git@github.com:thisisbramiller/FusionCloudX-Infrastructure.git`
   - Branch: `main`
   - SSH Key: Select the deploy key
4. Create task templates (see [Semaphore Configuration](#semaphore-configuration))

---

## SSH Key Management

### Three SSH Keys Strategy

Semaphore-ui uses **three separate SSH keys** for different purposes:

#### 1. Management Key (`~/.ssh/id_ed25519`)

**Purpose**: Access to ALL managed infrastructure (VMs, LXCs, containers)

**Used By**: Ansible to connect to hosts

**Distribution**: Public key added to `~/.ssh/authorized_keys` on all managed hosts

**Configuration**:
```bash
Host 192.168.*
  User ansible
  IdentityFile ~/.ssh/id_ed25519
```

#### 2. GitHub Deploy Key (`~/.ssh/github_deploy_key`)

**Purpose**: Access to GitHub repository

**Used By**: Git operations (clone, pull, push)

**Distribution**: Public key added to GitHub repository deploy keys

**Configuration**:
```bash
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_deploy_key
```

**GitHub Setup**:
1. Go to: `https://github.com/thisisbramiller/FusionCloudX-Infrastructure/settings/keys`
2. Click "Add deploy key"
3. Paste public key content
4. ✓ "Allow write access" (if you want to push from Semaphore)

#### 3. Proxmox Terraform Key (`~/.ssh/proxmox_terraform_key`)

**Purpose**: Terraform authentication to Proxmox

**Used By**: Terraform bpg/proxmox provider

**Distribution**: Public key added to Proxmox `terraform` user (or `root`)

**Configuration**:
```bash
Host proxmox 192.168.40.206
  HostName 192.168.40.206
  User terraform
  IdentityFile ~/.ssh/proxmox_terraform_key
```

**Proxmox Setup**:
```bash
ssh root@192.168.40.206
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo 'PUBLIC_KEY' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

### SSH Key Lifecycle

**Generation**: Automatically during bootstrap (if not exists)

**Storage**: `~/.ssh/` on semaphore-ui VM

**Backup**: Store private keys in 1Password (optional but recommended)

**Rotation**: Manual process:
1. Generate new keys
2. Distribute new public keys
3. Test access with new keys
4. Remove old keys from authorized_keys

**Security**:
- Ed25519 keys (modern, secure)
- 256-bit security
- Passphrase-less (for automation)
- Restricted to ansible user

---

## Repository Management

### Repository Location

**Path**: `/opt/infrastructure`

**Owner**: `ansible:ansible`

**Permissions**: `0755`

### Git Configuration

**Remote**: `git@github.com:thisisbramiller/FusionCloudX-Infrastructure.git`

**Branch**: `main` (configurable)

**Authentication**: SSH deploy key (`~/.ssh/github_deploy_key`)

**User Config**:
```
user.name = "Semaphore Control Plane"
user.email = "semaphore@fusioncloudx.home"
```

### Repository Sync Strategy

**Option 1: Manual Pull (Recommended for homelab)**

```bash
# SSH to semaphore-ui
ssh ansible@semaphore-ui

# Pull latest changes
cd /opt/infrastructure
git pull origin main
```

**Option 2: Semaphore Task Template**

Create a task in Semaphore:
- Name: "Update Repository"
- Type: Shell
- Command: `cd /opt/infrastructure && git pull origin main`
- Run manually when needed

**Option 3: GitHub Webhook (Advanced)**

Configure GitHub webhook to trigger Semaphore:
- URL: `http://semaphore:3000/api/project/1/tasks`
- Events: Push to main branch
- Semaphore executes git pull

**Option 4: Cron Job**

```bash
# Add to ansible user's crontab
*/15 * * * * cd /opt/infrastructure && git pull origin main --quiet
```

### Committing Changes from Semaphore

If you allow write access on the deploy key:

```bash
# Make changes
cd /opt/infrastructure
# ... edit files ...

# Commit and push
git add .
git commit -m "Update configuration from Semaphore"
git push origin main
```

**Note**: For homelab, it's often better to make changes on your workstation and pull them to Semaphore.

---

## 1Password Integration

### Architecture Choice: 1Password CLI vs Connect

**For Homelab: Use 1Password CLI** ✓

**Why**:
- Simpler setup (no Connect server needed)
- Lower resource usage
- Service account token is sufficient
- Easier to maintain

**1Password Connect** (optional):
- Requires separate Connect server
- Better for teams (more granular access control)
- API-based architecture
- Overkill for single-user homelab

### Setup 1Password CLI

#### 1. Create Service Account

1. Go to [1Password.com](https://my.1password.com)
2. Settings → Service Accounts
3. Create new service account
4. Name: "Semaphore Control Plane"
5. Vaults: Select your homelab vault
6. Permissions: Read (or Read + Write if needed)
7. **COPY THE TOKEN** (shown only once!)

#### 2. Configure Token on Semaphore

**Method A: Environment Variable (Recommended)**

```bash
# Edit /etc/default/semaphore
OP_SERVICE_ACCOUNT_TOKEN="ops_xxx..."
```

**Method B: Ansible User Profile**

```bash
# Add to ~/.bashrc
export OP_SERVICE_ACCOUNT_TOKEN="ops_xxx..."
```

#### 3. Test Connection

```bash
# SSH to semaphore-ui
ssh ansible@semaphore-ui

# Test 1Password CLI
op vault list
# Should show your vaults

# Get a secret
op item get "database-password" --vault "homelab" --fields password
```

### Using Secrets in Ansible

**With onepassword.connect collection**:

```yaml
- name: Get database password
  set_fact:
    db_password: "{{ lookup('onepassword.connect.generic', 'database-password', vault='homelab', field='password') }}"
```

**Environment variable**:

```yaml
- name: Get database password
  ansible.builtin.shell: op item get "database-password" --vault "homelab" --fields password
  register: db_password
  no_log: true
```

### Using Secrets in Terraform

**Install 1Password Provider**:

```hcl
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
  }
}

provider "onepassword" {
  # Uses OP_SERVICE_ACCOUNT_TOKEN environment variable
}
```

**Read Secrets**:

```hcl
data "onepassword_item" "db_password" {
  vault = "homelab"
  title = "database-password"
}

resource "some_resource" "example" {
  password = data.onepassword_item.db_password.password
}
```

**Create Secrets**:

```hcl
resource "onepassword_item" "api_key" {
  vault = "homelab"
  title = "semaphore-api-key"
  category = "password"

  password = random_password.api_key.result
}
```

### Best Practices

**DO**:
- ✓ Store service account token in environment variable
- ✓ Use `no_log: true` when handling secrets in Ansible
- ✓ Use separate service accounts for different purposes
- ✓ Rotate service account tokens periodically
- ✓ Store SSH private keys in 1Password as backup

**DON'T**:
- ✗ Hardcode secrets in playbooks or Terraform
- ✗ Commit service account tokens to git
- ✗ Share service account tokens between environments
- ✗ Log secret values in Semaphore output

---

## Semaphore Configuration

### Initial Setup

After bootstrap, complete these steps in Semaphore UI:

#### 1. Create Admin User

First time visiting `http://semaphore:3000`:
- **Username**: `admin`
- **Email**: `admin@fusioncloudx.home`
- **Name**: Your name
- **Password**: Strong password (store in 1Password!)

#### 2. Add Repository

**Settings → Repositories → New Repository**:
- **Name**: `FusionCloudX Infrastructure`
- **Git URL**: `git@github.com:thisisbramiller/FusionCloudX-Infrastructure.git`
- **Branch**: `main`
- **Key**: Select the SSH deploy key
- **Test Connection**: Should succeed

#### 3. Add Environment

**Settings → Environments → New Environment**:
- **Name**: `Production`
- **Variables**:
  ```json
  {
    "ANSIBLE_HOST_KEY_CHECKING": "False",
    "ANSIBLE_FORCE_COLOR": "True",
    "TF_VAR_proxmox_api_url": "https://192.168.40.206:8006"
  }
  ```

#### 4. Add Inventory

**Settings → Inventory → New Inventory**:
- **Name**: `Homelab`
- **Type**: `Static`
- **Inventory**:
  ```ini
  [all:vars]
  ansible_user=ansible
  ansible_python_interpreter=/usr/bin/python3

  [postgresql]
  postgresql ansible_host=192.168.1.XXX

  [application_servers]
  semaphore-ui ansible_host=192.168.1.XXX
  teleport ansible_host=192.168.1.XXX
  immich ansible_host=192.168.1.XXX

  [monitoring]
  wazuh ansible_host=192.168.1.XXX
  ```

### Task Templates

Task templates are the heart of Semaphore. Here are examples:

#### Terraform Apply

**Settings → Task Templates → New Template**:
- **Name**: `Deploy Infrastructure (Terraform Apply)`
- **Type**: `Deploy`
- **Repository**: `FusionCloudX Infrastructure`
- **Environment**: `Production`
- **Inventory**: `None` (Terraform doesn't use inventory)
- **Playbook**: Leave empty
- **Override CLI**: ✓
- **CLI Arguments**:
  ```bash
  cd /opt/infrastructure/terraform && terraform init && terraform apply -auto-approve
  ```

#### Terraform Plan

- **Name**: `Plan Infrastructure (Terraform Plan)`
- **CLI Arguments**:
  ```bash
  cd /opt/infrastructure/terraform && terraform init && terraform plan
  ```

#### Configure All Hosts

- **Name**: `Configure All Hosts`
- **Type**: `Deploy`
- **Repository**: `FusionCloudX Infrastructure`
- **Environment**: `Production`
- **Inventory**: `Homelab`
- **Playbook**: `ansible/playbooks/site.yml`

#### Update Inventory

- **Name**: `Update Inventory from Terraform`
- **Type**: `Build`
- **CLI Arguments**:
  ```bash
  cd /opt/infrastructure/terraform && terraform output -json > /tmp/tf-output.json
  cd /opt/infrastructure && ./scripts/update-inventory.sh
  ```

#### Configure Specific Service

- **Name**: `Configure PostgreSQL`
- **Playbook**: `ansible/playbooks/postgresql.yml`
- **Limit**: `postgresql`

### Running Tasks

1. Click "Tasks" in sidebar
2. Select task template
3. Click "Run Task"
4. Monitor real-time output
5. View logs and history

---

## Day-to-Day Workflow

### Typical Development Workflow

#### 1. Make Changes on Workstation

```bash
# On your workstation
cd FusionCloudX-Infrastructure

# Create feature branch
git checkout -b feature/new-vm

# Make changes to Terraform or Ansible
vim terraform/variables.tf
vim ansible/playbooks/site.yml

# Test locally (optional)
cd terraform && terraform plan

# Commit and push
git add .
git commit -m "Add new VM configuration"
git push origin feature/new-vm
```

#### 2. Update Control Plane

```bash
# SSH to semaphore-ui
ssh ansible@semaphore-ui

# Pull latest changes
cd /opt/infrastructure
git fetch origin
git checkout feature/new-vm
```

**OR** use Semaphore task template to pull changes.

#### 3. Run via Semaphore

1. Open Semaphore UI
2. Select appropriate task template:
   - Terraform Plan → Preview changes
   - Terraform Apply → Deploy infrastructure
   - Configure Hosts → Apply Ansible playbooks
3. Click "Run"
4. Monitor output
5. Verify changes

#### 4. Merge to Main

```bash
# On your workstation
git checkout main
git merge feature/new-vm
git push origin main

# On semaphore-ui
cd /opt/infrastructure
git checkout main
git pull origin main
```

### Common Tasks

#### Deploy New VM

1. Update `terraform/variables.tf` (add VM to `vm_configs`)
2. Run "Terraform Apply" in Semaphore
3. Wait for provisioning
4. Run "Update Inventory" to get new VM IP
5. Run "Configure All Hosts" to configure new VM

#### Update Application Configuration

1. Modify Ansible playbook or role
2. Push to GitHub
3. Pull changes to semaphore-ui
4. Run specific playbook via Semaphore
5. Verify changes on target hosts

#### Scheduled Tasks

Configure in Semaphore:
- **Nightly backups**: Schedule "Backup Infrastructure" task
- **Weekly updates**: Schedule "System Updates" playbook
- **Daily inventory sync**: Schedule "Update Inventory" task

#### Emergency Rollback

1. Identify last known good commit: `git log`
2. Revert repository: `git checkout COMMIT_HASH`
3. Run Terraform/Ansible from Semaphore
4. Verify infrastructure state
5. Fix forward or stay on good commit

### Team Collaboration

**Multiple Users**:
1. Each person gets Semaphore account
2. Assign roles (Admin, User, Guest)
3. All run tasks through Semaphore
4. Audit trail shows who ran what

**Preventing Conflicts**:
- Use Terraform locks (enable remote state)
- Coordinate via chat/tickets before changes
- Use feature branches for testing
- Review Semaphore logs before running

---

## Troubleshooting

### Bootstrap Issues

**Problem**: Cannot SSH to semaphore-ui

```bash
# Check if VM is running
terraform output vm_ipv4_addresses

# Verify SSH service
ssh -v ansible@SEMAPHORE_IP

# Check cloud-init completion
ssh ansible@SEMAPHORE_IP 'cat /var/lib/cloud-init.semaphore.ready'
```

**Problem**: Ansible playbook fails during bootstrap

```bash
# Run with verbose output
ansible-playbook -vvv -i 'IP,' playbooks/bootstrap-semaphore.yml

# Check Ansible connection
ansible -i 'IP,' all -m ping -u ansible
```

**Problem**: 1Password CLI fails to authenticate

```bash
# Verify token is set
ssh ansible@SEMAPHORE_IP 'echo $OP_SERVICE_ACCOUNT_TOKEN'

# Test CLI
ssh ansible@SEMAPHORE_IP 'op vault list'

# Check token format (should start with ops_)
```

### Runtime Issues

**Problem**: Semaphore cannot connect to GitHub

```bash
# Test SSH to GitHub
ssh ansible@SEMAPHORE_IP 'ssh -T git@github.com'

# Verify deploy key
cat ~/.ssh/github_deploy_key.pub
# Check this is added to GitHub deploy keys

# Check SSH config
cat ~/.ssh/config | grep -A5 github.com
```

**Problem**: Terraform cannot authenticate to Proxmox

```bash
# Test SSH to Proxmox
ssh -i ~/.ssh/proxmox_terraform_key terraform@192.168.40.206

# Verify key is in authorized_keys on Proxmox
ssh root@192.168.40.206 'cat /root/.ssh/authorized_keys'

# Check environment variable
echo $PROXMOX_VE_ENDPOINT
```

**Problem**: Ansible cannot connect to managed hosts

```bash
# Test individual host
ansible -i inventory/hosts.ini postgresql -m ping

# Check SSH key
cat ~/.ssh/id_ed25519.pub

# Verify key on target host
ssh ansible@TARGET_HOST 'cat ~/.ssh/authorized_keys'

# Check inventory
cat ansible/inventory/hosts.ini
```

**Problem**: Semaphore UI not accessible

```bash
# Check service status
sudo systemctl status semaphore

# Check logs
sudo journalctl -u semaphore -f

# Verify port
sudo netstat -tlnp | grep 3000

# Test locally
curl http://localhost:3000
```

**Problem**: Database connection failed

```bash
# Test PostgreSQL connectivity
nc -zv postgresql 5432

# Test authentication
PGPASSWORD='password' psql -h postgresql -U semaphore -d semaphore -c '\l'

# Check Semaphore config
cat /etc/semaphore/config.json | jq '.postgres'
```

### Logs and Diagnostics

**Semaphore Logs**:
```bash
sudo journalctl -u semaphore -f
```

**Ansible Logs** (in Semaphore UI):
- Tasks → Task History → View Output

**Terraform Logs**:
```bash
# Enable debug logging
export TF_LOG=DEBUG
terraform plan
```

**Cloud-init Logs**:
```bash
# Check cloud-init status
cloud-init status

# View logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

---

## Security Considerations

### Network Security

- **Firewall**: Only allow SSH (22) and Semaphore (3000) ports
- **VPN**: Consider VPN access for Semaphore UI (WireGuard/Tailscale)
- **Reverse Proxy**: Use Nginx with SSL for production

### Access Control

- **Semaphore Users**: Create individual accounts, no shared passwords
- **SSH Keys**: Unique keys per purpose, no password auth
- **1Password**: Use service accounts, not personal accounts
- **Sudo**: ansible user has NOPASSWD (acceptable for homelab, review for production)

### Secrets Management

- **Never commit secrets** to git
- **Use 1Password** for all sensitive data
- **Rotate tokens** periodically
- **Audit access** via Semaphore logs

### Backup Strategy

**Critical Data**:
- `/opt/infrastructure` (git repo - backed up to GitHub)
- `/etc/semaphore/config.json` (Semaphore config)
- `~/.ssh/` (SSH keys - backup to 1Password)
- PostgreSQL database (semaphore database backup)

**Backup Script**:
```bash
#!/bin/bash
# Backup control plane critical data
tar -czf /tmp/semaphore-backup.tar.gz \
  /opt/infrastructure \
  /etc/semaphore \
  /home/ansible/.ssh

# Upload to backup location
rsync -av /tmp/semaphore-backup.tar.gz backup-server:/backups/
```

---

## Summary

You now have a production-quality Infrastructure Control Plane running on semaphore-ui. All infrastructure automation runs through Semaphore UI, providing:

✓ Centralized automation
✓ Web-based management
✓ Complete audit trail
✓ Team collaboration
✓ Secure secrets management
✓ Scheduled tasks

**Next Steps**:
1. Complete Semaphore initial setup
2. Create task templates for common operations
3. Test running playbooks and Terraform
4. Document your specific workflows
5. Train team members on using Semaphore

**Remember**: This is a homelab, so iterate and improve. The architecture is solid, but customize it to fit your needs!

---

**Questions? Issues?**

Check the [Troubleshooting](#troubleshooting) section or review Semaphore logs. For Semaphore-specific help, see the [official documentation](https://docs.semaphoreui.com/).
