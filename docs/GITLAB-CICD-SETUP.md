# GitLab CI/CD Setup Guide

This guide explains how to configure and use GitLab CI/CD for manual infrastructure operations, replacing Semaphore UI with native GitLab features.

## Overview

**Architecture**: GitLab serves as both version control AND execution platform
- **Version Control**: Git repository hosting
- **CI/CD**: Automated validation + manual job execution
- **Manual Triggers**: Click-to-run jobs (similar to Rundeck/Semaphore UI)
- **No Additional Infrastructure**: No separate control plane VM needed

## Prerequisites

### 1. GitLab Instance
- GitLab CE/EE installed and running (see `ansible/playbooks/gitlab.yml`)
- Access to GitLab web UI at `http://gitlab.fusioncloudx.home`
- Admin access to configure CI/CD settings

### 2. GitLab Runner
You need a GitLab Runner to execute CI/CD jobs. Two options:

**Option A: Docker Runner (Recommended for Homelab)**
```bash
# On any host with Docker (can be GitLab VM itself)
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest

# Register the runner
docker exec -it gitlab-runner gitlab-runner register
# Follow prompts:
# - GitLab URL: http://gitlab.fusioncloudx.home
# - Registration token: Get from GitLab UI → Settings → CI/CD → Runners
# - Description: homelab-docker-runner
# - Tags: docker,terraform,ansible
# - Executor: docker
# - Default image: alpine:latest
```

**Option B: Shell Runner (On GitLab VM)**
```bash
# Install runner on GitLab VM
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install gitlab-runner

# Register runner
sudo gitlab-runner register
# Same prompts as above, but executor: shell

# Install dependencies (Terraform, Ansible) on GitLab VM
sudo apt-get install -y terraform ansible
```

### 3. SSH Access Configuration

GitLab Runner needs SSH access to managed hosts:

```bash
# On GitLab VM or Runner host, generate SSH key
ssh-keygen -t ed25519 -f ~/.ssh/ansible_key -N ""

# Add public key to all managed hosts (postgresql, etc.)
# Method 1: Via cloud-init (add to user_data_cloud_config)
# Method 2: Manually append to /home/ansible/.ssh/authorized_keys on each host

# Test connectivity
ssh -i ~/.ssh/ansible_key ansible@192.168.40.121  # PostgreSQL IP
```

### 4. 1Password Integration

GitLab Runner needs access to 1Password Connect for secrets:

```bash
# Set environment variables on runner host
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_service_account_token_here"
export OP_CONNECT_HOST="http://your-1password-connect-host:8080"
export TF_VAR_onepassword_vault_id="your-vault-uuid"

# For persistent configuration, add to runner's environment
# Docker runner: Edit /srv/gitlab-runner/config/config.toml
# Shell runner: Edit /etc/gitlab-runner/config.toml

[[runners]]
  environment = [
    "OP_SERVICE_ACCOUNT_TOKEN=ops_...",
    "OP_CONNECT_HOST=http://...:8080",
    "TF_VAR_onepassword_vault_id=..."
  ]
```

## GitLab CI/CD Variables Setup

Configure secrets in GitLab UI:

1. Navigate to **Settings → CI/CD → Variables**
2. Add the following variables:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `PROXMOX_VE_ENDPOINT` | `https://192.168.40.206:8006` | No | No |
| `PROXMOX_VE_USERNAME` | `terraform@pve` | No | No |
| `PROXMOX_VE_PASSWORD` | `your-proxmox-password` | Yes | Yes |
| `PROXMOX_VE_INSECURE` | `true` | No | No |
| `OP_SERVICE_ACCOUNT_TOKEN` | `ops_your_token` | Yes | Yes |
| `TF_VAR_onepassword_vault_id` | `your-vault-uuid` | Yes | No |
| `ANSIBLE_PRIVATE_KEY` | `(contents of ansible_key)` | Yes | Yes |

**Note**: For `ANSIBLE_PRIVATE_KEY`, paste the entire private key content including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`.

## Repository Setup

Push this repository to your GitLab instance:

```bash
# Add GitLab remote
git remote add gitlab http://gitlab.fusioncloudx.home/homelab/infrastructure.git

# Push to GitLab (creates project if using blank project)
git push gitlab main

# OR: Import repository in GitLab UI
# GitLab → New Project → Import Project → Repository by URL
# Git repository URL: (your current remote or local path)
```

## Using Manual Jobs

### Workflow: Provision Infrastructure

1. **Edit Terraform files** (e.g., add new VM to `terraform/variables.tf`)
2. **Commit and push**:
   ```bash
   git add terraform/variables.tf
   git commit -m "feat: add monitoring VM"
   git push gitlab main
   ```
3. **GitLab auto-runs**: `terraform:init` and `terraform:validate`
4. **Navigate to Pipeline**: GitLab → CI/CD → Pipelines → Click latest pipeline
5. **Click ▶ on `terraform:plan`**: Preview infrastructure changes
6. **Review plan output**: Check what will be created/modified/destroyed
7. **Click ▶ on `terraform:apply`**: Provision infrastructure
8. **Wait for completion**: View real-time logs
9. **Click ▶ on `update:inventory`**: Export Terraform outputs
10. **Download artifact**: `terraform-outputs.json` contains VM IPs
11. **Update inventory**: Edit `ansible/inventory/hosts.ini` with IPs
12. **Commit inventory update**: `git add ansible/inventory/hosts.ini && git commit && git push`

### Workflow: Configure Hosts with Ansible

1. **Navigate to Pipeline**: Latest pipeline with updated inventory
2. **Click ▶ on `ansible:ping`**: Test connectivity to all hosts
3. **Click ▶ on specific playbook**:
   - `ansible:postgresql` - Configure PostgreSQL database server
   - `ansible:gitlab` - Configure GitLab instance
   - `ansible:site` - Run all playbooks (full configuration)
4. **Monitor logs**: Real-time Ansible output in GitLab UI
5. **Verify success**: Green checkmark means playbook completed successfully

### Workflow: Destroy Infrastructure

**WARNING**: This is destructive and cannot be undone.

1. **Navigate to Pipeline**: CI/CD → Pipelines
2. **Click ▶ on `terraform:destroy`**: Destroys ALL Terraform-managed resources
3. **Confirm**: Type confirmation if prompted
4. **Wait for completion**: All VMs/LXCs will be destroyed

## Manual Job Reference

| Job | Stage | Purpose | When to Use |
|-----|-------|---------|-------------|
| `terraform:init` | validate | Initialize Terraform | Auto-runs on every pipeline |
| `terraform:validate` | validate | Validate Terraform syntax | Auto-runs after init |
| `terraform:plan` | plan | Preview infrastructure changes | Before applying changes |
| `terraform:apply` | apply | Provision infrastructure | After reviewing plan |
| `terraform:destroy` | destroy | Destroy all infrastructure | Tear down homelab |
| `ansible:ping` | configure | Test host connectivity | After provisioning VMs |
| `ansible:postgresql` | configure | Configure PostgreSQL | After PostgreSQL VM/LXC ready |
| `ansible:gitlab` | configure | Configure GitLab | After GitLab VM ready |
| `ansible:site` | configure | Run all Ansible playbooks | Full configuration run |
| `update:inventory` | plan | Export Terraform IPs | After terraform:apply |

## Troubleshooting

### Runner Not Picking Up Jobs

**Symptom**: Jobs stuck in "Pending" state

**Solutions**:
1. Check runner status: `docker exec gitlab-runner gitlab-runner verify`
2. Ensure runner is enabled in GitLab UI → Settings → CI/CD → Runners
3. Check runner tags match job requirements
4. Restart runner: `docker restart gitlab-runner`

### Terraform Authentication Failed

**Symptom**: `Error: unable to authenticate to Proxmox`

**Solutions**:
1. Verify `PROXMOX_VE_*` variables in GitLab settings
2. Ensure `PROXMOX_VE_INSECURE=true` if using self-signed cert
3. Test Proxmox API manually:
   ```bash
   curl -k https://192.168.40.206:8006/api2/json/version
   ```

### Ansible SSH Connection Failed

**Symptom**: `UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh"}`

**Solutions**:
1. Verify `ANSIBLE_PRIVATE_KEY` variable contains full private key
2. Ensure public key is in `/home/ansible/.ssh/authorized_keys` on target hosts
3. Check inventory has correct IP addresses
4. Test SSH manually from runner:
   ```bash
   ssh -i /path/to/ansible_key ansible@target-ip
   ```

### 1Password Secrets Not Found

**Symptom**: `Error: onepassword.connect.field_info: item not found`

**Solutions**:
1. Verify `OP_SERVICE_ACCOUNT_TOKEN` is set correctly
2. Check `OP_CONNECT_HOST` points to 1Password Connect server
3. Ensure 1Password Connect server is running and accessible
4. Verify vault ID and item names match exactly

## Comparison to Semaphore UI

| Feature | Semaphore UI | GitLab CI/CD |
|---------|--------------|--------------|
| Manual job execution | ✅ Click to run | ✅ Click to run (`when: manual`) |
| Real-time logs | ✅ Web UI | ✅ Web UI |
| Job history | ✅ | ✅ |
| RBAC | ✅ | ✅ (GitLab users/groups) |
| Secret management | ✅ | ✅ (CI/CD variables) |
| Infrastructure required | ❌ Separate VM (8GB) | ✅ Uses existing GitLab |
| Version control integration | Manual sync | ✅ Native git integration |
| Automated triggers | ❌ Manual only | ✅ Git push triggers available |

**Key Advantages of GitLab CI/CD**:
- No additional infrastructure (saves 8GB RAM)
- Native git integration (auto-trigger on push)
- Single platform for code + execution
- Industry-standard CI/CD platform
- Can add automation later (scheduled pipelines, merge request triggers)

**Similar to Rundeck** (user's CVS experience):
- Manual job execution (click to run)
- Real-time log viewing
- Job history and audit trail
- But integrated with version control instead of standalone

## Next Steps

1. **Complete GitLab Runner setup** (see Prerequisites)
2. **Configure CI/CD variables** in GitLab UI
3. **Test manual jobs**: Start with `ansible:ping`, then `terraform:plan`
4. **Update documentation**: Add homelab-specific details
5. **Consider automation**: Add scheduled pipelines for backups, health checks

## Related Documentation

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [Manual Jobs Documentation](https://docs.gitlab.com/ee/ci/jobs/job_control.html#create-a-job-that-must-be-run-manually)
- Christian Lempa's approach: [homelab repository](https://github.com/ChristianLempa/homelab)
