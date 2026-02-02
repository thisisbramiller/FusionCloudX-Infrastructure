# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing **homelab/development** infrastructure on Proxmox Virtual Environment (PVE) using Terraform and Ansible. The repository uses **GitLab CI/CD** for both version control and automated/manual job execution, eliminating the need for separate automation tooling.

## GitLab CI/CD Architecture

### Overview

The infrastructure uses GitLab CI/CD as the central platform for both version control and execution:
- **Version Control**: Git repository hosted in GitLab
- **CI/CD**: Automated validation + manual job execution via GitLab pipelines
- **Manual Triggers**: Click-to-run jobs using `when: manual` (similar to Rundeck)
- **No Separate Control Plane**: GitLab provides both code hosting and execution platform
- PostgreSQL LXC container hosts databases (wazuh, etc.)

### Key Components

**GitLab VM**:
- VM ID 1103, 8GB RAM, 4 CPU cores
- Runs GitLab CE Omnibus on port 80/443
- Hosts infrastructure repository
- Provides CI/CD web UI for manual job execution
- Access: http://gitlab.fusioncloudx.home

**GitLab Runner**:
- Executes CI/CD jobs (Docker or Shell executor)
- Installed on GitLab VM or separate host
- Has access to Terraform, Ansible, and managed infrastructure
- Configured with secrets via GitLab CI/CD variables

**Database Server (postgresql)**:
- LXC container ID 2001, 4GB RAM, 2 CPU cores
- Debian 12 unprivileged container
- Hosts multiple databases: wazuh, future applications
- Managed by Ansible role `postgresql`

### Execution Model

**Automated Jobs** (run on git push):
- `terraform:init` - Initialize Terraform providers
- `terraform:validate` - Validate Terraform syntax and formatting

**Manual Jobs** (click-to-run in GitLab UI):
- `terraform:plan` - Preview infrastructure changes
- `terraform:apply` - Provision infrastructure
- `terraform:destroy` - Destroy all infrastructure (destructive)
- `ansible:ping` - Test connectivity to managed hosts
- `ansible:postgresql` - Configure PostgreSQL server
- `ansible:gitlab` - Configure GitLab instance
- `ansible:site` - Run all Ansible playbooks

See `docs/GITLAB-CICD-SETUP.md` for detailed setup and usage instructions.

## Terraform Structure

Configuration files in `terraform/`:

- `provider.tf` - Proxmox provider (bpg/proxmox v0.93.0) + 1Password provider. Uses Proxmox API (`endpoint`) for most operations, SSH with agent auth (user `terraform`) for certain actions like file uploads. Connects to `192.168.40.206:8006`
- `backend.tf` - Local state backend (`terraform.tfstate` at project root)
- `variables.tf` - Defines `vm_configs` (QEMU VMs), `postgresql_lxc_config` (single LXC), `postgresql_databases` (database list), and `onepassword_vault_id`
- `ubuntu-template.tf` - Creates VM template (ID 1000) from Ubuntu Noble cloud image
- `cloud-init.tf` - Split cloud-init: per-VM user_data + shared vendor_data. **Special**: `gitlab_vendor_data_cloud_config` has enhanced packages for GitLab
- `qemu-vm.tf` - Creates VMs using `for_each`. GitLab gets special vendor_data. Uses 10 retries for clone operations
- `lxc-postgresql.tf` - Single Debian 12 LXC for PostgreSQL + 1Password items for database credentials
- `lxc-template-automation.tf` - Automated custom LXC template creation (sudo, python3, ssh-import-id pre-installed)
- `outputs.tf` - VM IPv4 addresses map from QEMU guest agent

### Key Terraform Patterns

**VM Provisioning Flow**:
1. Download Ubuntu Noble cloud image → create template (ID 1000)
2. For each VM in `vm_configs`: create user_data, reference vendor_data (standard or gitlab-specific)
3. Clone template with full clone, apply cloud-init
4. QEMU guest agent reports IP address to outputs

**LXC Container Pattern** (Fully Automated):
- Single PostgreSQL LXC hosts multiple databases (not one LXC per database)
- **Custom template**: Terraform automatically creates Ansible-ready template with sudo, python3, ssh-import-id pre-installed
- **Automation**: null_resource copies and runs template creation script on Proxmox via SSH (no manual steps)
- Unprivileged container for security
- Ansible handles PostgreSQL installation and database creation
- 1Password items created via Terraform for each database user
- See `docs/LXC-TEMPLATE-SETUP.md` for details

**1Password Integration**:
- Terraform creates 1Password items for database passwords
- Ansible retrieves secrets via `onepassword.connect` collection
- Service account token passed via `OP_SERVICE_ACCOUNT_TOKEN` environment variable

**Current Infrastructure** (from `variables.tf`):
- **VMs**:
  - `gitlab` (ID 1103, 8GB/4 cores) - Git hosting + CI/CD + manual job execution
- **LXC**: `postgresql` (ID 2001, 4GB/2 cores) - database server
- **Databases**: wazuh (defined in `postgresql_databases` variable)

## Ansible Structure

Configuration in `ansible/`:

- `ansible.cfg` - Uses `./inventory/hosts.ini`, disables host key checking
- `requirements.yml` - Collections: `onepassword.connect`, `community.general`, `community.postgresql`
- `inventory/hosts.ini` - Groups: `[postgresql]`, `[application_servers]`, `[monitoring]`, meta-group `[homelab]`
- `inventory/group_vars/vault.yml` - Ansible Vault encrypted secrets (fallback for 1Password)
- `inventory/group_vars/postgresql.yml` - PostgreSQL-specific variables
- `inventory/host_vars/postgresql.yml` - Database definitions and user configuration
- `playbooks/postgresql.yml` - PostgreSQL installation and database setup
- `playbooks/gitlab.yml` - GitLab installation and configuration
- `playbooks/site.yml` - Main playbook (orchestrates all roles)
- `roles/postgresql/` - Installs PostgreSQL, creates databases/users, configures remote access
- `roles/gitlab/` - Installs GitLab CE Omnibus, configures memory-constrained settings

### Ansible Vault vs 1Password

**1Password (preferred)**:
- Use for production secrets
- Ansible collection: `onepassword.connect`
- Service account token in environment variable
- Secrets retrieved at playbook runtime

**Ansible Vault (fallback)**:
- File: `inventory/group_vars/vault.yml`
- Encrypt: `ansible-vault encrypt group_vars/vault.yml`
- Edit: `ansible-vault edit group_vars/vault.yml`
- Variables prefixed with `vault_` (e.g., `vault_postgresql_admin_password`)

### Key Ansible Roles

**postgresql**:
- Installs PostgreSQL 15+ on Debian 12 LXC
- Creates databases and users from `postgresql_databases` variable
- Configures `pg_hba.conf` for remote access (homelab network)
- Templates: `postgresql.conf.j2`, `pg_hba.conf.j2`
- Handlers: restart PostgreSQL on config changes
- Secrets: Retrieves database passwords from 1Password Connect via `onepassword.connect.field_info`

**gitlab**:
- Installs GitLab CE Omnibus package
- Configures memory-constrained settings for 8GB RAM (Puma workers: 0, Sidekiq: 10)
- Sets up external URL and initial root password from 1Password
- Templates: `gitlab.rb.j2`
- Handlers: gitlab-ctl reconfigure on config changes

## Common Commands

### Initial Setup (GitLab CI/CD)

Setup GitLab CI/CD for infrastructure automation:

```bash
# 1. Provision GitLab VM with Terraform
cd terraform/
terraform init
terraform plan
terraform apply

# 2. Configure GitLab with Ansible
cd ../ansible/
ansible-playbook playbooks/gitlab.yml

# 3. Setup GitLab Runner (on GitLab VM or separate host)
# See docs/GITLAB-CICD-SETUP.md for detailed instructions

# 4. Push repository to GitLab
git remote add gitlab http://gitlab.fusioncloudx.home/homelab/infrastructure.git
git push gitlab main

# 5. Configure CI/CD variables in GitLab UI
# Settings → CI/CD → Variables
# Required: PROXMOX_VE_*, OP_SERVICE_ACCOUNT_TOKEN, TF_VAR_onepassword_vault_id

# 6. Test manual jobs in GitLab UI
# CI/CD → Pipelines → Click pipeline → Click ▶ on terraform:plan
```

### Terraform (from Workstation or GitLab CI/CD)

Work from `terraform/` directory:

```bash
# Initialize and download providers
terraform init

# Plan infrastructure changes
terraform plan

# Apply infrastructure (provisions VMs/LXCs, creates 1Password items)
terraform apply

# Get VM IP addresses
terraform output vm_ipv4_addresses

# Get specific output
terraform output postgresql_lxc_ipv4_address

# Destroy specific resource
terraform destroy -target=proxmox_virtual_environment_vm.qemu-vm[\"gitlab\"]

# Destroy all infrastructure (use with caution)
terraform destroy
```

### Ansible (from Control Plane or Workstation)

Work from `ansible/` directory:

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Run main site playbook (all hosts, all roles)
ansible-playbook playbooks/site.yml

# Run specific playbook
ansible-playbook playbooks/postgresql.yml

# Limit to specific host or group
ansible-playbook playbooks/site.yml --limit postgresql

# Check connectivity to all hosts
ansible all -m ping

# Check specific group
ansible postgresql -m ping

# Ad-hoc command on all hosts
ansible all -a "uptime"

# Use vault password for encrypted variables
ansible-playbook playbooks/site.yml --ask-vault-pass

# Edit vault-encrypted file
ansible-vault edit inventory/group_vars/vault.yml
```

### Inventory Management

Update Ansible inventory with Terraform-provisioned IPs:

```bash
# PowerShell version (Windows)
./ansible/update-inventory.ps1

# Bash version (Linux/Mac)
./ansible/update-inventory.sh

# Manual approach
cd terraform/
terraform output -json > /tmp/tf-outputs.json
# Parse JSON and update ansible/inventory/hosts.ini
```

### GitLab CI/CD Operations

Use GitLab UI at `http://gitlab.fusioncloudx.home`:

1. **Update repository**: Commit and push changes to GitLab
2. **Preview infrastructure**: Navigate to CI/CD → Pipelines → Click ▶ on `terraform:plan`
3. **Deploy infrastructure**: Click ▶ on `terraform:apply` (after reviewing plan)
4. **Configure hosts**: Click ▶ on `ansible:postgresql` or `ansible:site`
5. **View logs**: Real-time output in GitLab job logs
6. **Scheduled pipelines**: Configure in CI/CD → Schedules (for backups, health checks)

### 1Password CLI (for local development)

```bash
# List vaults
op vault list

# Get secret from 1Password
op item get "database-password" --vault "homelab" --fields password

# Test service account token
echo $OP_SERVICE_ACCOUNT_TOKEN
op vault list  # Should succeed if token is valid
```

## Important Notes

### Proxmox Authentication
- **Primary**: Proxmox API via HTTPS endpoint (`192.168.40.206:8006`)
- **Secondary**: SSH agent authentication for specific operations (file uploads, etc.)
  - User: `terraform` on Proxmox host
  - SSH agent must have key loaded (or 1Password SSH agent integration)
- Provider configuration: `insecure = false` for SSL verification (update if using self-signed certs)
- Most resources use API; SSH only for operations requiring direct file access
- GitLab CI/CD: Authenticate via `PROXMOX_VE_*` environment variables (configured in GitLab settings)

### 1Password Integration

**Service Account Token**:
- **1Password Service Account Token** (`OP_SERVICE_ACCOUNT_TOKEN`): Used by Terraform and Ansible
- Connect Server: http://192.168.40.44:8080 (self-hosted 1Password Connect)

**Usage by Tool**:
- **Terraform**: Uses 1Password provider to create credential items (database passwords, GitLab root password)
- **Ansible**: Uses `onepassword.connect` collection to retrieve secrets at runtime
- **GitLab CI/CD**: Service account token configured as masked CI/CD variable
- **Vault ID**: Set `TF_VAR_onepassword_vault_id` for Terraform (required)

**Environment Variables** (for local development):
- `OP_SERVICE_ACCOUNT_TOKEN` - Service account token
- `OP_CONNECT_TOKEN` - JWT token for 1Password Connect server
- `OP_CONNECT_HOST` - 1Password Connect server URL
- `TF_VAR_onepassword_vault_id` - Vault UUID
- `PROXMOX_VE_API_TOKEN` - Proxmox API authentication

**GitLab CI/CD Variables** (configured in GitLab UI):
- `OP_SERVICE_ACCOUNT_TOKEN` - Masked variable for 1Password access
- `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD` - Proxmox authentication
- `TF_VAR_onepassword_vault_id` - Vault UUID

**Fallback**: Ansible Vault (`inventory/group_vars/vault.yml`) for secrets when 1Password unavailable

### Resource Dependencies
- VMs depend on template (ID 1000) via `depends_on` in `qemu-vm.tf`
- **PostgreSQL LXC depends on custom template** via `depends_on` in `lxc-postgresql.tf` (automated by null_resource)
- Custom LXC template creation runs before PostgreSQL container (fully automated)
- Cloud-init files must exist before VM initialization
- PostgreSQL LXC must be provisioned before running `postgresql.yml` playbook
- GitLab VM must be configured before using CI/CD pipelines
- GitLab Runner must be registered before running CI/CD jobs

### Infrastructure Specifics

**Datastores**:
- `nas-infrastructure` - Cloud images, cloud-init snippets, LXC templates
- `vm-data` - VM/LXC disks, runtime cloud-init configs

**VM Specifications**:
- Template: VM ID 1000, Ubuntu Noble, node "pve"
- VMs: Full clones (not linked), x86-64-v2-AES CPU, DHCP networking
- Clone operations: 10 retries for storage lock handling
- Auto-start: `on_boot = true` by default (VMs start with Proxmox host)

**LXC Specifications**:
- PostgreSQL: Unprivileged container, Debian 12, VM ID 2001
- Network: DHCP on vmbr0
- Features: Nesting enabled (for potential Docker use)

**Cloud-Init Behavior**:
- **Standard VMs**: Basic vendor_data (qemu-guest-agent, python3, pip)
- **gitlab**: Enhanced vendor_data (curl, postfix, ufw, python3 for Ansible)
- User: `ansible` with NOPASSWD sudo, SSH keys from GitHub (`thisisbramiller`)
- Marker files: `/var/lib/cloud-init.provision.ready` (all VMs), `/var/lib/cloud-init.gitlab.ready` (GitLab)

**GitLab Configuration**:
- **VM**: gitlab (ID 1103, 8GB RAM, 4 CPU cores, 50GB disk)
- **Installation**: GitLab CE Omnibus (latest stable)
- **Database**: Embedded PostgreSQL (managed by Omnibus)
- **Configuration**: Memory-constrained (`/etc/gitlab/gitlab.rb`)
- **Access**: http://gitlab.fusioncloudx.home
- **Credentials**: 1Password (GitLab Root User)

**Memory-Constrained Settings**:
- Puma workers: 0 (single process mode)
- Sidekiq concurrency: 10
- Prometheus: disabled
- Supports: 1-10 users with 8GB RAM

**Common GitLab Commands**:
```bash
# Reconfigure after editing gitlab.rb
sudo gitlab-ctl reconfigure

# Check service status
sudo gitlab-ctl status

# View logs
sudo gitlab-ctl tail

# Create backup
sudo gitlab-backup create

# Restart all services
sudo gitlab-ctl restart
```

### State Management
- Terraform state: Local backend (`terraform.tfstate` at project root)
- State file is gitignored
- No locking or collaboration support (use remote backend for teams)
- GitLab CI/CD approach: Runner maintains state, accessible as pipeline artifact
- Consider migrating to remote backend (S3, GitLab Managed Terraform State) for collaboration

### Secrets Management Strategy

**DO**:
- Store passwords/tokens in 1Password
- Use `no_log: true` in Ansible for secret handling
- Rotate 1Password service account tokens periodically
- Encrypt `vault.yml` with ansible-vault as fallback

**DON'T**:
- Commit secrets to git (use `.gitignore` for sensitive files)
- Share service account tokens between environments
- Log secrets in GitLab CI/CD job output (use `no_log: true` in Ansible, masked variables in GitLab)
- Use Ansible Vault as primary secrets store (1Password preferred)

## Development Workflow

### GitLab CI/CD Workflow (Recommended)

1. **Make changes on workstation**: Edit Terraform/Ansible files
2. **Commit and push to GitLab**:
   ```bash
   git add terraform/variables.tf
   git commit -m "feat: add monitoring VM"
   git push gitlab main
   ```
3. **GitLab auto-validates**: `terraform:init` and `terraform:validate` run automatically
4. **Execute manual jobs in GitLab UI**:
   - Navigate to CI/CD → Pipelines → Click latest pipeline
   - Click ▶ on `terraform:plan` to preview changes
   - Review plan output in job logs
   - Click ▶ on `terraform:apply` to provision infrastructure
   - Click ▶ on `update:inventory` to export IPs
   - Update `ansible/inventory/hosts.ini` with IPs, commit and push
   - Click ▶ on `ansible:postgresql` or `ansible:site` to configure hosts
5. **Monitor and verify**: Real-time logs in GitLab job output, green checkmarks indicate success

### Local Development Workflow (Without GitLab CI/CD)

1. Modify Terraform configurations in `terraform/` directory
2. Run `terraform plan` to preview changes
3. Run `terraform apply` to provision infrastructure
4. Get VM IPs: `terraform output vm_ipv4_addresses`
5. Update Ansible inventory: `./ansible/update-inventory.sh`
6. Run Ansible playbooks: `ansible-playbook playbooks/site.yml`

### Adding New Infrastructure

**Add VM**:
1. Update `variables.tf` → add entry to `vm_configs` map
2. `terraform apply` → provisions VM with cloud-init
3. Update inventory → run update script or manual edit
4. Configure with Ansible → `ansible-playbook playbooks/site.yml`

**Add Database**:
1. Update `variables.tf` → add entry to `postgresql_databases` list
2. `terraform apply` → creates 1Password item for credentials
3. Update `host_vars/postgresql.yml` → define database and user
4. Run playbook → `ansible-playbook playbooks/postgresql.yml`

**Add Ansible Role**:
1. Create role in `ansible/roles/role-name/`
2. Define tasks, handlers, defaults, templates
3. Include role in `playbooks/site.yml` or dedicated playbook
4. Add manual job to `.gitlab-ci.yml` for the new playbook
5. Run playbook via GitLab CI/CD or command line

## Current Branch

Current branch: `feat/remove-semaphore-use-gitlab-cicd` (replacing Semaphore UI with GitLab CI/CD)
Main branch for PRs: `main`

## Environment Context

**Homelab/Development Infrastructure**: This repository manages Proxmox-based homelab infrastructure for testing and development. Services deployed: GitLab (version control + CI/CD), PostgreSQL (databases), planned services (Teleport, Wazuh, Immich). Production workloads will use separate AWS infrastructure.

**Security Posture**: Appropriate for homelab (NOPASSWD sudo, self-signed certs, `insecure = true`). Review security settings before adapting for production use.

## Certificate Management

### Overview

Certificate deployment integrates with the `fusioncloudx-bootstrap` repository:
- **Bootstrap Repository:** Generates PKI (Phase 04), deploys to bare metal (Phase 13)
- **Infrastructure Repository:** Deploys certificates to VMs via Ansible

### Architecture

**Certificate Flow:**
1. **Bootstrap Phase 04:** Generate Root CA, Intermediate CA, Server Certificate → Store in 1Password
2. **Bootstrap Phase 13:** Deploy CA to Mac Mini, deploy server certs to Proxmox hosts
3. **Infrastructure Ansible:** Retrieve from 1Password → Deploy to VMs via `certificates` role

**Separation of Concerns:**
- **Bootstrap:** Bare metal only (Mac Mini workstation + Proxmox echo/zero)
- **Infrastructure:** VMs and services (semaphore-ui, gitlab, postgresql)

### Ansible Role: certificates

**Location:** `ansible/roles/certificates/`

**Features:**
- Installs Root CA + Intermediate CA to system trust store
- Deploys server certificate and private key to `/etc/ssl/`
- Configures nginx for HTTPS (optional)
- Handles service restarts automatically

**Usage:**
```bash
# Deploy to all hosts
ansible-playbook ansible/playbooks/site.yml --tags certificates

# Test on single host
ansible-playbook ansible/playbooks/test-certificates.yml --limit semaphore-ui

# Deploy to specific host
ansible-playbook ansible/playbooks/common.yml --limit gitlab
```

**Variables:**
```yaml
certificates_install_ca: true           # Install CA to trust store
certificates_deploy_server: true        # Deploy server cert/key
certificates_configure_nginx: false     # Configure nginx SSL
```

### Optional Network Devices

**Location:** `ansible/inventory/devices.yaml`, `ansible/playbooks/optional/deploy-device-certificates.yml`

**Included Devices:**
- HP OfficeJet Pro 9015e (network printer)
- UniFi Dream Machine Pro (network appliance)
- UNAS Pro (storage appliance)

**Deployment:** Manual import via device web interfaces (instructions provided by playbook)

**Usage:**
```bash
ansible-playbook ansible/playbooks/optional/deploy-device-certificates.yml
```

### Integration Points

**1Password:**
- Certificates stored in FusionCloudX vault
- Retrieved via 1Password CLI during Ansible runs
- Requires `OP_SERVICE_ACCOUNT_TOKEN` environment variable

**Bootstrap Repository:**
- Phase 04 generates all certificates
- Phase 13 deploys to bare metal (workstation + Proxmox)
- Source of truth for PKI infrastructure

**Verification:**
```bash
# Check CA installation
ls /usr/local/share/ca-certificates/fusioncloudx-*.crt

# Check server certificate
ls /etc/ssl/certs/server.crt
ls /etc/ssl/private/server.key

# Verify trust store
grep -r "FusionCloudX" /etc/ssl/certs/ca-certificates.crt
```

### Decision Tree: Certificate Deployment

**Is it bare metal?** → Bootstrap repository (Phase 13)
**Is it a VM?** → Infrastructure repository (certificates role)
**Is it optional (printer, appliance)?** → Infrastructure repository (optional playbook, manual)

See `ansible/roles/certificates/README.md` and `docs/DEVICE-CERTIFICATE-DEPLOYMENT.md` for detailed documentation.
