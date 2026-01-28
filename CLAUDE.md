# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing **homelab/development** infrastructure on Proxmox Virtual Environment (PVE) using Terraform and Ansible. The repository follows a **Control Plane architecture** where the `semaphore-ui` VM serves as a centralized automation hub running Terraform and Ansible through a web interface.

## Control Plane Architecture

### Overview

The infrastructure uses Semaphore UI (running on `semaphore-ui` VM) as the control plane:
- All Terraform/Ansible operations run through Semaphore web UI
- Infrastructure repository cloned to `/opt/infrastructure` on semaphore-ui
- 1Password CLI integration for secrets management
- Three SSH keys for different purposes (management, GitHub, Proxmox)
- PostgreSQL LXC container hosts databases (semaphore, wazuh, etc.)

### Key Components

**Control Plane VM (semaphore-ui)**:
- VM ID 1102, 8GB RAM, 8 CPU cores
- Runs Semaphore UI on port 3000
- Hosts: Terraform 1.10+, Ansible 2.18+, 1Password CLI
- Repository path: `/opt/infrastructure`
- User: `ansible` (NOPASSWD sudo)

**Database Server (postgresql)**:
- LXC container ID 2001, 4GB RAM, 2 CPU cores
- Debian 12 unprivileged container
- Hosts multiple databases: semaphore, wazuh
- Managed by Ansible role `postgresql`

**SSH Key Strategy**:
1. `~/.ssh/id_ed25519` - Management key for all managed hosts
2. `~/.ssh/github_deploy_key` - GitHub repository access
3. `~/.ssh/proxmox_terraform_key` - Terraform authentication to Proxmox

### Bootstrap Process

**Three-phase bootstrap**:
1. **Cloud-init** (automatic): Installs base packages via enhanced vendor_data for semaphore-ui
2. **Workstation bootstrap** (one-time): Run `./scripts/bootstrap-control-plane.sh` or manually execute `ansible/playbooks/bootstrap-semaphore.yml`
3. **Self-management** (ongoing): All operations run through Semaphore UI

After bootstrap, update Semaphore UI with repository, create task templates, and manage infrastructure through the web interface. See `docs/CONTROL-PLANE.md` for detailed architecture documentation.

## Terraform Structure

Configuration files in `terraform/`:

- `provider.tf` - Proxmox provider (bpg/proxmox v0.93.0) + 1Password provider. Uses Proxmox API (`endpoint`) for most operations, SSH with agent auth (user `terraform`) for certain actions like file uploads. Connects to `192.168.40.206:8006`
- `backend.tf` - Local state backend (`terraform.tfstate` at project root)
- `variables.tf` - Defines `vm_configs` (QEMU VMs), `postgresql_lxc_config` (single LXC), `postgresql_databases` (database list), and `onepassword_vault_id`
- `ubuntu-template.tf` - Creates VM template (ID 1000) from Ubuntu Noble cloud image
- `cloud-init.tf` - Split cloud-init: per-VM user_data + shared vendor_data. **Special**: `semaphore_vendor_data_cloud_config` has enhanced packages for control plane
- `qemu-vm.tf` - Creates VMs using `for_each`. Semaphore-ui gets special vendor_data. Uses 10 retries for clone operations
- `lxc-postgresql.tf` - Single Debian 12 LXC for PostgreSQL + 1Password items for database credentials
- `outputs.tf` - VM IPv4 addresses map from QEMU guest agent

### Key Terraform Patterns

**VM Provisioning Flow**:
1. Download Ubuntu Noble cloud image → create template (ID 1000)
2. For each VM in `vm_configs`: create user_data, reference vendor_data (standard or semaphore-specific)
3. Clone template with full clone, apply cloud-init
4. QEMU guest agent reports IP address to outputs

**LXC Container Pattern**:
- Single PostgreSQL LXC hosts multiple databases (not one LXC per database)
- Unprivileged container for security
- Ansible handles PostgreSQL installation and database creation
- 1Password items created via Terraform for each database user

**1Password Integration**:
- Terraform creates 1Password items for database passwords
- Ansible retrieves secrets via `onepassword.connect` collection
- Service account token passed via `OP_SERVICE_ACCOUNT_TOKEN` environment variable

**Current Infrastructure** (from `variables.tf`):
- **VMs**:
  - `semaphore-ui` (ID 1102, 8GB/8 cores) - control plane
  - `gitlab` (ID 1103, 8GB/4 cores) - Git hosting + CI/CD
- **LXC**: `postgresql` (ID 2001, 4GB/2 cores) - database server
- **Databases**: semaphore, wazuh (defined in `postgresql_databases` variable)

## Ansible Structure

Configuration in `ansible/`:

- `ansible.cfg` - Uses `./inventory/hosts.ini`, disables host key checking
- `requirements.yml` - Collections: `onepassword.connect`, `community.general`, `community.postgresql`
- `inventory/hosts.ini` - Groups: `[postgresql]`, `[application_servers]`, `[monitoring]`, meta-group `[homelab]`
- `inventory/group_vars/vault.yml` - Ansible Vault encrypted secrets (fallback for 1Password)
- `inventory/group_vars/postgresql.yml` - PostgreSQL-specific variables
- `inventory/host_vars/postgresql.yml` - Database definitions and user configuration
- `playbooks/bootstrap-semaphore.yml` - **One-time** control plane bootstrap playbook
- `playbooks/postgresql.yml` - PostgreSQL installation and database setup
- `playbooks/site.yml` - Main playbook (orchestrates all roles)
- `roles/semaphore-controller/` - Installs Terraform, 1Password CLI, Semaphore UI, SSH keys, clones repo
- `roles/postgresql/` - Installs PostgreSQL, creates databases/users, configures remote access

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

**semaphore-controller** (bootstrap only):
- Tasks: install-terraform, install-onepassword, install-semaphore, install-ansible-collections, ssh-keys, clone-repo, configure-environment, verify-installation
- Generates 3 SSH keys, installs Terraform 1.10.3, 1Password CLI 2.30.3, Semaphore UI
- Clones repo to `/opt/infrastructure`, configures systemd service
- Run once from workstation to bootstrap control plane

**postgresql**:
- Installs PostgreSQL 15+ on Debian 12 LXC
- Creates databases and users from `postgresql_databases` variable
- Configures `pg_hba.conf` for remote access (homelab network)
- Templates: `postgresql.conf.j2`, `pg_hba.conf.j2`
- Handlers: restart PostgreSQL on config changes

## Common Commands

### Initial Setup (One-Time Bootstrap)

Bootstrap the control plane from your workstation:

```bash
# Guided bootstrap script (recommended)
./scripts/bootstrap-control-plane.sh

# Manual bootstrap (if script fails)
cd ansible/
ansible-playbook \
  -i 'SEMAPHORE_IP,' \
  -u ansible \
  playbooks/bootstrap-semaphore.yml \
  -e "onepassword_service_account_token=$OP_SERVICE_ACCOUNT_TOKEN"

# Note: OP_SERVICE_ACCOUNT_TOKEN loaded from ~/.zprofile (macOS Keychain)

# After bootstrap, configure GitHub deploy key
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/github_deploy_key.pub'
# Add to GitHub: Repository → Settings → Deploy keys

# Configure Proxmox SSH access
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/proxmox_terraform_key.pub'
# Add to Proxmox terraform user's authorized_keys
```

### Terraform (from Control Plane or Workstation)

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
terraform destroy -target=proxmox_virtual_environment_vm.qemu-vm[\"semaphore-ui\"]

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

### Control Plane Operations (via Semaphore UI)

After bootstrap, use Semaphore UI at `http://semaphore-ui:3000`:

1. **Update repository**: Task template or manual `git pull` in `/opt/infrastructure`
2. **Deploy infrastructure**: Run Terraform task template (plan/apply)
3. **Configure hosts**: Run Ansible playbook task template
4. **Scheduled tasks**: Configure cron-like schedules in Semaphore

### 1Password CLI (on Control Plane)

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
  - On control plane: Uses dedicated SSH key at `~/.ssh/proxmox_terraform_key`
  - SSH agent must have key loaded (or 1Password SSH agent integration)
- Provider configuration: `insecure = false` for SSL verification (update if using self-signed certs)
- Most resources use API; SSH only for operations requiring direct file access

### 1Password Integration

**Dual Authentication Setup**:
- **1Password Service Account Token** (`OP_SERVICE_ACCOUNT_TOKEN`): Used by bootstrap playbook for initial semaphore-ui setup
- **1Password Connect** (`OP_CONNECT_TOKEN` + `OP_CONNECT_HOST`): Used by Ansible collections for ongoing secret retrieval
- Connect Server: http://192.168.40.44:8080 (self-hosted 1Password Connect)

**Usage by Tool**:
- **Terraform**: Uses 1Password provider to create credential items (database passwords, GitLab root password)
- **Ansible Bootstrap**: Uses service account token (`OP_SERVICE_ACCOUNT_TOKEN`) passed as extra var
- **Ansible Operations**: Uses `onepassword.connect` collection with Connect server credentials
- **Vault ID**: Set `TF_VAR_onepassword_vault_id` for Terraform (required)

**Environment Variables** (loaded from ~/.zprofile via macOS Keychain):
- `OP_SERVICE_ACCOUNT_TOKEN` - Service account token (for bootstrap)
- `OP_CONNECT_TOKEN` - JWT token for 1Password Connect server
- `OP_CONNECT_HOST` - 1Password Connect server URL
- `TF_VAR_onepassword_vault_id` - Vault UUID
- `PROXMOX_VE_API_TOKEN` - Proxmox API authentication

**Fallback**: Ansible Vault (`inventory/group_vars/vault.yml`) for secrets when 1Password unavailable

### Resource Dependencies
- VMs depend on template (ID 1000) via `depends_on` in `qemu-vm.tf`
- LXC depends on Debian 12 template download
- Cloud-init files must exist before VM initialization
- PostgreSQL LXC must be provisioned before running `postgresql.yml` playbook
- Semaphore-ui must be bootstrapped before managing infrastructure through UI

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
- **semaphore-ui**: Enhanced vendor_data (ansible, terraform, git, build-essential)
- **gitlab**: Enhanced vendor_data (curl, postfix, ufw, python3 for Ansible)
- User: `ansible` with NOPASSWD sudo, SSH keys from GitHub (`thisisbramiller`)
- Marker files: `/var/lib/cloud-init.provision.ready` (all VMs), `/var/lib/cloud-init.semaphore.ready` (control plane), `/var/lib/cloud-init.gitlab.ready` (GitLab)

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
- Control plane approach: Run Terraform from semaphore-ui to centralize state

### Secrets Management Strategy

**DO**:
- Store passwords/tokens in 1Password
- Use `no_log: true` in Ansible for secret handling
- Rotate 1Password service account tokens periodically
- Encrypt `vault.yml` with ansible-vault as fallback

**DON'T**:
- Commit secrets to git (use `.gitignore` for sensitive files)
- Share service account tokens between environments
- Log secrets in Semaphore/Ansible output
- Use Ansible Vault as primary secrets store (1Password preferred)

## Development Workflow

### Day-to-Day (Control Plane Approach)

1. **Make changes on workstation**: Edit Terraform/Ansible files, commit to git
2. **Update control plane**: SSH to semaphore-ui, `git pull` in `/opt/infrastructure`, or use Semaphore task
3. **Execute via Semaphore UI**: Run Terraform plan/apply or Ansible playbook through web interface
4. **Monitor and verify**: View logs in Semaphore, check infrastructure state

### Traditional Workflow (Without Control Plane)

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
4. Run playbook via Semaphore or command line

## Current Branch

Current branch: `semaphore-ui` (active development of control plane)
Main branch for PRs: `main`

## Environment Context

**Homelab/Development Infrastructure**: This repository manages Proxmox-based homelab infrastructure for testing and development. Services deployed: Semaphore (automation), PostgreSQL (databases), planned services (Teleport, Wazuh, Immich). Production workloads will use separate AWS infrastructure.

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
