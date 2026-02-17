# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing **homelab/development** infrastructure on Proxmox Virtual Environment (PVE) using Terraform and Ansible.

## Infrastructure Components

**GitLab VM** (ID 1103):
- 16GB RAM, 8 CPU cores during installation (can reduce to 8GB/4 cores after)
- GitLab CE Omnibus with HTTPS enabled
- Access: https://gitlab.fusioncloudx.home
- Memory-constrained settings: Puma workers=0, Sidekiq concurrency=10, Prometheus disabled

**PostgreSQL LXC** (ID 2001):
- Debian 12 unprivileged container, 4GB RAM, 2 CPU cores, 64GB disk
- Hosts multiple databases (currently: wazuh)
- Standard Proxmox Debian 12 template with Ansible bootstrap

## Architecture

```
Terraform (Provisioning)                    Ansible (Configuration)
├── Create VM template (ID 1000)            ├── bootstrap playbook (raw: python3, sudo)
├── Clone VMs from template                 ├── certificates role (CA + server certs)
├── Create LXC from standard template       ├── postgresql role (install, configure)
├── Create 1Password items                  ├── gitlab role (install, configure)
└── Generate Ansible inventory              └── Dynamic inventory via Terraform state
```

**Key Design Decisions**:
- Single PostgreSQL instance hosts all databases (not one container per database)
- Standard Proxmox templates with Ansible `raw` module bootstrap (no custom template building needed)
- 1Password is primary secrets store; Ansible Vault is fallback
- Dynamic inventory reads directly from Terraform state

## Terraform Structure

Files in `terraform/`:

| File | Purpose |
|------|---------|
| `provider.tf` | Proxmox (bpg/proxmox v0.93.0), 1Password (~3.0), Ansible (~1.3.0) providers |
| `backend.tf` | Local state backend |
| `variables.tf` | `vm_configs`, `postgresql_lxc_config`, `postgresql_databases`, `onepassword_vault_id` |
| `ubuntu-template.tf` | VM template (ID 1000) from Ubuntu Noble cloud image |
| `cloud-init.tf` | Standard cloud-init (user_data + vendor_data) |
| `cloud-init-gitlab.tf` | Enhanced cloud-init for GitLab (postfix, ufw, etc.) |
| `qemu-vm.tf` | VMs via `for_each` from `vm_configs`; 10 clone retries |
| `lxc-debian-template.tf` | Downloads Debian 12 LXC template |
| `lxc-postgresql.tf` | PostgreSQL LXC container definition |
| `ssh-keys.tf` | Ansible SSH key generation (`tls_private_key`) |
| `onepassword.tf` | All 1Password items (SSH key, PostgreSQL, GitLab, Tandoor credentials) |
| `ansible-inventory.tf` | Dynamic inventory via Terraform Ansible provider |
| `outputs.tf` | Infrastructure summary, URLs, 1Password item IDs |

**Proxmox Connection**:
- API: https://192.168.40.206:8006 (primary for most operations)
- SSH: User `terraform` via SSH agent (for file operations like template creation)

**Datastores**:
- `nas-infrastructure`: Cloud images, cloud-init snippets, LXC templates
- `vm-data`: VM/LXC disks

## Ansible Structure

Files in `ansible/`:

| Path | Purpose |
|------|---------|
| `ansible.cfg` | Dynamic inventory, SSH config, fact caching |
| `requirements.yml` | `onepassword.connect >=2.3.0`, `community.general` |
| `inventory/terraform.yml` | Dynamic inventory plugin (reads Terraform state) |
| `inventory/group_vars/all.yml` | Global: timezone, DNS, NTP, firewall |
| `inventory/group_vars/postgresql.yml` | PostgreSQL tuning, HBA rules |
| `inventory/host_vars/postgresql.yml` | Database definitions, firewall rules |
| `inventory/host_vars/gitlab.yml` | GitLab domain, memory settings, HTTPS config |
| `inventory/group_vars/vault.yml` | Encrypted fallback secrets (Ansible Vault) |

**Roles**:
- `ssh-key-loader/`: Retrieves SSH key from 1Password Connect for playbook authentication
- `certificates/`: Retrieves certs from 1Password, installs CA to trust store, deploys server cert/key
- `postgresql/`: Installs PostgreSQL 15, creates databases/users, configures pg_hba.conf
- `gitlab/`: Installs GitLab CE Omnibus, configures gitlab.rb with memory-constrained settings

**Playbooks**:
- `site.yml`: Main orchestration (contains inlined plays for bootstrap, common, postgresql, gitlab)
- `bootstrap.yml`: LXC container prerequisite installation (python3, sudo via raw module)
- `common.yml`: Certificate deployment
- `postgresql.yml`: Database server configuration
- `gitlab.yml`: GitLab installation and configuration

**Inventory Groups**:
- `postgresql`: LXC containers (root SSH access)
- `application_servers`: QEMU VMs (ansible user, NOPASSWD sudo)
- `homelab`: Meta-group containing all

## Common Commands

### Terraform (from `terraform/` directory)

```bash
terraform init                    # Download providers
terraform plan                    # Preview changes
terraform apply                   # Provision infrastructure
terraform output infrastructure_summary  # View all resources
terraform output gitlab_url       # Get GitLab URL
terraform output postgresql_connection   # Get PostgreSQL connection info
terraform destroy -target=proxmox_virtual_environment_vm.qemu-vm[\"gitlab\"]  # Destroy specific resource
```

### Ansible (from `ansible/` directory)

```bash
ansible-galaxy collection install -r requirements.yml  # Install collections
ansible-playbook playbooks/site.yml                   # Run all playbooks
ansible-playbook playbooks/postgresql.yml             # PostgreSQL only
ansible-playbook playbooks/gitlab.yml                 # GitLab only
ansible-playbook playbooks/common.yml --limit gitlab  # Certificates for gitlab
ansible all -m ping                                   # Test connectivity
ansible-inventory --graph                             # View dynamic inventory
```

### Certificate Deployment

```bash
ansible-playbook playbooks/site.yml --tags certificates     # All hosts
ansible-playbook playbooks/test-certificates.yml --limit gitlab  # Test single host
```

### GitLab Administration (on gitlab VM)

```bash
sudo gitlab-ctl reconfigure    # Apply gitlab.rb changes
sudo gitlab-ctl status         # Service status
sudo gitlab-ctl tail           # View logs
sudo gitlab-backup create      # Create backup
```

### 1Password CLI

```bash
op vault list                                              # List vaults
op item get "GitLab Root User" --vault homelab --fields password  # Get password
```

## Environment Variables

| Variable | Purpose | Required By |
|----------|---------|-------------|
| `OP_CONNECT_HOST` | 1Password Connect server URL | Ansible (ssh-key-loader, secrets) |
| `OP_CONNECT_TOKEN` | 1Password Connect authentication | Ansible (ssh-key-loader, secrets) |
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password authentication | Terraform |
| `TF_VAR_onepassword_vault_id` | 1Password vault UUID | Terraform, Ansible |
| `PROXMOX_VE_API_TOKEN` | Proxmox API authentication | Terraform |
| `SSH_AUTH_SOCK` | SSH agent socket (auto-set) | Terraform SSH operations |

## Resource Dependencies

```
Ubuntu Template (ID 1000)              Standard Debian 12 Template
    ↓                                  (downloaded from Proxmox)
GitLab VM (ID 1103) ──────────────┐         ↓
                                  │    PostgreSQL LXC (ID 2001)
                                  ↓         │
                            Ansible playbooks
                            (bootstrap → common → apps)
```

## Adding New Infrastructure

**Add VM**: Update `vm_configs` in `variables.tf` → `terraform apply` → `ansible-playbook playbooks/site.yml`

**Add Database**: Update `postgresql_databases` in `variables.tf` → Update `host_vars/postgresql.yml` → `terraform apply` → `ansible-playbook playbooks/postgresql.yml`

**Add Ansible Role**: Create `roles/<name>/` with tasks, handlers, templates → Include in playbook → Run playbook

## 1Password Items Created by Terraform

| Item | Type | Contents |
|------|------|----------|
| Infrastructure Ansible SSH Key | Secure Note | ED25519 private/public key pair |
| PostgreSQL Admin (postgres) | Database | postgres user credentials |
| PostgreSQL - Wazuh Database User | Database | wazuh user credentials |
| PostgreSQL - Mealie Database User | Database | mealie user credentials |
| PostgreSQL - Tandoor Database User | Database | tandoor user credentials |
| GitLab Root User | Login | root username, 32-char password |
| GitLab Runner Registration Token | Password | 32-char alphanumeric token |
| Tandoor Secret Key | Password | 50-char Django SECRET_KEY |

## Certificate Management

Certificates integrate with the `fusioncloudx-bootstrap` repository:
1. **Bootstrap Phase 04**: Generates Root CA, Intermediate CA, Server Certificate → stores in 1Password
2. **Bootstrap Phase 13**: Deploys to bare metal (Mac Mini, Proxmox hosts)
3. **Infrastructure Ansible**: Retrieves from 1Password → deploys to VMs via `certificates` role

**Decision Tree**:
- Bare metal → Bootstrap repository (Phase 13)
- VMs/containers → Infrastructure repository (certificates role)
- Network devices (printer, appliance) → Infrastructure optional playbook (manual import)

## LXC Container Bootstrap

LXC containers use standard Proxmox Debian 12 templates. Since these templates don't include Python, the Ansible `bootstrap.yml` playbook uses the `raw` module to install prerequisites before other playbooks run.

**Bootstrap Process**:
1. Terraform creates LXC from standard Debian 12 template
2. Bootstrap playbook runs `raw` module (works without Python)
3. Installs `python3` and `sudo` via apt
4. Subsequent playbooks can use standard Ansible modules

**Run Bootstrap**:
```bash
ansible-playbook playbooks/bootstrap.yml        # Bootstrap LXC containers
ansible-playbook playbooks/site.yml             # Full deployment (includes bootstrap)
```

## Cloud-Init Configuration

**Standard VMs**: User `ansible` with NOPASSWD sudo, SSH keys from GitHub (`thisisbramiller`), qemu-guest-agent, python3

**GitLab VM**: Enhanced packages (curl, postfix, ufw, openssh-server), preconfigured hostname, UFW rules, marker files for readiness detection

**LXC Containers**: No cloud-init (uses standard template with Ansible raw module bootstrap)

## Git Workflow

Main branch: `main`

## SSH Key Management

Ansible SSH keys are managed through 1Password Connect for automated, secure access:

**Architecture**:
1. **Terraform** generates ED25519 SSH key pair via `tls_private_key`
2. **Terraform** stores key in 1Password as "Infrastructure Ansible SSH Key" (secure_note)
3. **Ansible** cleans any leftover temp key from previous runs (clean-before-load)
4. **Ansible** retrieves fresh key from 1Password Connect via `ssh-key-loader` role
5. **Ansible** writes key to temp file (`/tmp/.ansible_ssh_key`) with 0600 permissions
6. **Ansible** cleans up temp file after playbook completion

**Clean-Before-Load Pattern**:
Similar to Jenkins `deleteDir()` at pipeline start, the `ssh-key-loader` role removes any existing temp key before loading a fresh one. This ensures failed runs don't leave stale keys and the next run always starts with a clean workspace.

**Why 1Password Connect (not SSH agent)**:
- 1Password Terraform provider only supports `secure_note` category (not `SSH_KEY`)
- 1Password SSH agent can only serve keys stored as SSH_KEY items
- Connect API allows retrieval of any field type, enabling full automation

**Security Considerations**:
| Aspect | Assessment |
|--------|-----------|
| Key at rest | Encrypted in 1Password |
| Key in transit | HTTPS to Connect server |
| Key in memory | Only during playbook execution |
| Temp file | Brief disk exposure (0600 perms, deleted after) |
| Audit trail | 1Password Connect logs all access |

## Security Notes

- **Homelab appropriate**: NOPASSWD sudo, `insecure = false` for SSL
- **Secrets in 1Password**: Never commit secrets; use `no_log: true` in Ansible tasks
- **State file gitignored**: `terraform.tfstate` contains sensitive data
- **SSH keys from GitHub**: Imported from user `thisisbramiller`
