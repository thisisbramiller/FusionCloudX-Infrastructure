# GitLab Self-Hosted Installation

This document describes the GitLab CE (Community Edition) installation on Proxmox for the FusionCloudX Infrastructure homelab.

## Overview

GitLab CE is deployed as a self-hosted Git repository and CI/CD platform using the Omnibus package with memory-constrained configuration optimized for homelab use.

## Specifications

### VM Configuration
- **VM ID**: 1103
- **Hostname**: gitlab.fusioncloudx.home
- **Resources**: 8GB RAM, 4 CPU cores, 50GB disk
- **OS**: Ubuntu 24.04 LTS (Noble)
- **Installation Method**: GitLab Omnibus package
- **Database**: Embedded PostgreSQL (managed by Omnibus)

### Memory-Constrained Configuration

Optimized for 1-10 users with repositories under 500MB:

```ruby
# /etc/gitlab/gitlab.rb
puma['worker_processes'] = 0  # Single process mode
sidekiq['concurrency'] = 10   # Reduced background job concurrency
prometheus_monitoring['enable'] = false  # Monitoring disabled
```

**Expected Memory Usage**: ~2.8GB (36% of 8GB allocation)

## Initial Setup

### 1. Access GitLab

Browse to: http://gitlab.fusioncloudx.home

### 2. First Login

1. **Username**: root
2. **Password**: Retrieved from 1Password (item: "GitLab Root User")
   ```bash
   # From workstation with OP CLI installed:
   op item get "GitLab Root User" --vault "FusionCloudX" --fields password
   ```
3. **Change root password immediately** after first login

### 3. Create Admin User

1. Navigate to Admin Area → Users
2. Create a new user with admin privileges
3. Use this account for daily operations (do not use root)

### 4. Configure SSH Keys

1. Navigate to User Settings → SSH Keys
2. Add your public SSH key for Git operations
3. Test SSH access:
   ```bash
   ssh -T git@gitlab.fusioncloudx.home
   ```

## Management Commands

### Service Management

```bash
# Check all service status
sudo gitlab-ctl status

# Reconfigure after editing /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure

# Restart all services
sudo gitlab-ctl restart

# Stop all services
sudo gitlab-ctl stop

# Start all services
sudo gitlab-ctl start
```

### Logs

```bash
# Tail all logs
sudo gitlab-ctl tail

# Tail specific service
sudo gitlab-ctl tail puma
sudo gitlab-ctl tail sidekiq
sudo gitlab-ctl tail nginx
```

### Health Checks

```bash
# Full system health check
sudo gitlab-rake gitlab:check

# Check environment info
sudo gitlab-rake gitlab:env:info

# Database health
sudo gitlab-rake gitlab:db:check
```

## Backup and Restore

### Manual Backup

```bash
# Create backup (stored in /var/opt/gitlab/backups)
sudo gitlab-backup create

# List backups
ls -lh /var/opt/gitlab/backups/
```

### Automated Backups

Configured in `/etc/gitlab/gitlab.rb`:
- **Retention**: 7 days
- **Path**: `/var/opt/gitlab/backups`

### Restore from Backup

```bash
# Stop services that connect to the database
sudo gitlab-ctl stop puma
sudo gitlab-ctl stop sidekiq

# Restore (replace TIMESTAMP with actual backup timestamp)
sudo gitlab-backup restore BACKUP=TIMESTAMP

# Restart GitLab
sudo gitlab-ctl restart

# Check status
sudo gitlab-rake gitlab:check SANITIZE=true
```

## Scaling Path

When user count grows beyond 10 users or memory usage exceeds 70%:

### 1. Increase VM Resources

Update `terraform/variables.tf`:
```hcl
"gitlab" = {
  vm_id      = 1103
  name       = "gitlab"
  memory_mb  = 16384  # 16GB
  cpu_cores  = 8
  started    = true
  full_clone = true
}
```

Apply changes:
```bash
cd terraform
terraform apply
```

### 2. Update GitLab Configuration

Edit `/etc/gitlab/gitlab.rb`:
```ruby
# Enable Puma clustering
puma['worker_processes'] = 4

# Increase Sidekiq concurrency
sidekiq['concurrency'] = 25

# Enable Prometheus (if needed)
prometheus_monitoring['enable'] = true
```

Reconfigure:
```bash
sudo gitlab-ctl reconfigure
```

## Firewall Configuration

UFW firewall configured via Ansible with the following rules:
- **HTTP (80)**: GitLab web interface
- **HTTPS (443)**: SSL/TLS access (when configured)
- **SSH (22)**: Git SSH operations

```bash
# Check firewall status
sudo ufw status

# Allow additional port (if needed)
sudo ufw allow 8080/tcp comment "Custom port"
```

## Troubleshooting

### GitLab Not Responding

```bash
# Check service status
sudo gitlab-ctl status

# Check if services are running
ps aux | grep gitlab

# Check memory usage
free -h

# Restart GitLab
sudo gitlab-ctl restart
```

### High Memory Usage

```bash
# Check memory usage by service
sudo gitlab-ctl status

# Reduce Puma workers (if needed)
# Edit /etc/gitlab/gitlab.rb:
puma['worker_processes'] = 0

# Reconfigure
sudo gitlab-ctl reconfigure
```

### Database Issues

```bash
# Check database status
sudo gitlab-rake gitlab:db:check

# Check PostgreSQL
sudo gitlab-ctl status postgresql

# Restart PostgreSQL
sudo gitlab-ctl restart postgresql
```

## GitLab CI/CD Setup

### 1. Install GitLab Runner

For infrastructure automation with Terraform/Ansible:

```bash
# On a dedicated runner VM or GitLab VM itself
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner
```

### 2. Register Runner

```bash
# Get registration token from 1Password
# Item: "GitLab Runner Registration Token"

sudo gitlab-runner register \
  --url http://gitlab.fusioncloudx.home \
  --registration-token YOUR_TOKEN \
  --executor shell \
  --description "Infrastructure Runner"
```

### 3. Create CI/CD Pipeline

Example `.gitlab-ci.yml` for infrastructure repo:

```yaml
stages:
  - validate
  - plan
  - apply

terraform-validate:
  stage: validate
  script:
    - cd terraform
    - terraform init
    - terraform validate

terraform-plan:
  stage: plan
  script:
    - cd terraform
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - terraform/tfplan

terraform-apply:
  stage: apply
  script:
    - cd terraform
    - terraform apply -auto-approve tfplan
  when: manual
  only:
    - main
```

## Security Considerations

### Current Configuration (Development/Homelab)

- **HTTP only** (no SSL/TLS)
- **No external access** (local network only)
- **Root password** stored in 1Password
- **Firewall**: UFW enabled, limited ports

### Production Hardening (Future)

When moving to production:

1. **Enable HTTPS**: Configure Let's Encrypt or self-signed certificates
2. **Restrict root access**: Disable root login after creating admin users
3. **Two-factor authentication**: Enable 2FA for all users
4. **External authentication**: Integrate with LDAP/SAML
5. **Network segmentation**: Place in DMZ or isolated network
6. **Regular backups**: Automate to external storage (NAS, S3)
7. **Monitoring**: Enable Prometheus/Grafana
8. **Security updates**: Enable automatic security patches

## Known Issues

### Ansible Roles Path

**Issue**: Ansible playbooks require `ANSIBLE_ROLES_PATH=./roles` when run from ansible directory.

**Workaround**: 
```bash
cd ansible
ANSIBLE_ROLES_PATH=./roles ansible-playbook playbooks/gitlab.yml
```

**Fix**: To be addressed in future commit - update ansible.cfg roles_path resolution.

## References

- **GitLab Docs**: https://docs.gitlab.com/
- **Omnibus Package**: https://docs.gitlab.com/omnibus/
- **Memory-Constrained Config**: https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/
- **Backup/Restore**: https://docs.gitlab.com/ee/administration/backup_restore/
- **CI/CD Runners**: https://docs.gitlab.com/runner/

## Maintenance Schedule

### Weekly
- Review backup retention (auto-managed, 7-day retention)
- Check disk usage: `df -h /var/opt/gitlab`

### Monthly
- Review user accounts and permissions
- Check for GitLab updates: `sudo apt-get update && apt-cache policy gitlab-ce`
- Review CI/CD runner status (when configured)

### Quarterly
- Update GitLab to latest stable version
- Review and update security settings
- Audit repository access and permissions
