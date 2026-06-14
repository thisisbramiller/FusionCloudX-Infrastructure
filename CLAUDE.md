# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FusionCloudX Infrastructure is an Infrastructure-as-Code repository for managing **homelab/development** infrastructure on Proxmox Virtual Environment (PVE) using OpenTofu and Ansible.

## Infrastructure Components

**GitLab VM** (ID 1103):
- 16GB RAM, 8 CPU cores during installation (can reduce to 8GB/4 cores after)
- GitLab CE Omnibus with HTTPS enabled
- Access: https://gitlab.fusioncloudx.home
- Memory-constrained settings: Puma workers=0, Sidekiq concurrency=10, Prometheus disabled

**Mealie VM** (ID 1104):
- 4GB RAM, 2 CPU cores, 32GB disk on vm-data (NFS)
- Mealie recipe management with Docker Compose + nginx SSL termination
- Access: https://mealie.fusioncloudx.home:9925

**Tandoor VM** (ID 1105):
- 4GB RAM, 2 CPU cores, 32GB disk on vm-data (NFS)
- Tandoor Recipes with Docker Compose + nginx SSL termination
- Access: https://tandoor.fusioncloudx.home:8080

**Immich VM** (ID 1106):
- 8GB RAM, 4 CPU cores, 32GB disk on `local-zfs` (NVMe SSD)
- Self-hosted photo management (Google Photos/iCloud replacement)
- 5-container Docker Compose stack: server, ML, redis (Valkey), PostgreSQL+pgvector, nginx
- Photo originals on UNAS Pro NFS (`immich_library`), database on local SSD
- Access: https://immich.fusioncloudx.home:9926

**Run It Up VM** (ID 1111):
- 2GB RAM, 2 CPU cores, 32GB disk on vm-data (NFS)
- "Run It Up" self-hosted savings-tracker PWA — SQLite-backed (no external DB)
- App builds from its synced source repo via the app's own multi-stage Dockerfile, fronted by an nginx sidecar for SSL termination (Docker Compose)
- SQLite data on a named volume bound to `/opt/runitup/data`
- Access: https://runitup.fusioncloudx.home:9929
- **DNS (manual step):** `runitup.fusioncloudx.home → <DHCP IP>` must be added as an A-record on the UDM. The wildcard cert (`*.fusioncloudx.home`) already covers this host — no new cert needed.

**PostgreSQL LXC** (ID 2001):
- Debian 12 unprivileged container, 4GB RAM, 2 CPU cores, 64GB disk
- Hosts multiple databases (currently: mealie, tandoor)
- Standard Proxmox Debian 12 template with Ansible bootstrap

## Architecture

```
OpenTofu (Provisioning)                     Ansible (Configuration)
├── Create VM template (ID 1000)            ├── bootstrap playbook (raw: python3, sudo)
├── Clone VMs from template                 ├── certificates role (CA + server certs)
├── Create LXC from standard template       ├── postgresql role (install, configure)
├── Create 1Password items                  ├── gitlab role (install, configure)
├── Per-VM datastore support                ├── mealie role (Docker, nginx, compose)
│   (local-zfs for Immich)                  ├── tandoor role (Docker, nginx, compose)
└── Generate Ansible inventory              ├── immich role (Docker, NFS, compose)
                                            └── Dynamic inventory via OpenTofu state
```

**Key Design Decisions**:
- Single PostgreSQL instance hosts all databases (not one container per database)
- Standard Proxmox templates with Ansible `raw` module bootstrap (no custom template building needed)
- 1Password is primary secrets store; Ansible Vault is fallback
- Dynamic inventory reads directly from OpenTofu state

## OpenTofu Structure

Config lives in `tofu/`, split into three independently-applied root states plus a shared module library. Each state has its own S3 + SSE-KMS remote backend.

```
tofu/
├── network/      # State 1: networking primitives consumed by everything downstream
├── opconnect/    # State 2: the VM that RUNS 1Password Connect (the secrets root)
├── compute/      # State 3: VMs, LXC, cloud-init, SSH keys, Ansible inventory, outputs
└── modules/      # Shared reusable modules consumed by the states above
```

**`tofu/network/`** — networking primitives (read by `opconnect` and `compute` via remote state).

**`tofu/opconnect/`** — State 2: the VM that runs 1Password Connect (the secrets root). It provisions VM 1101 + cloud-init + DNS and reads ONLY the bootstrap Ansible **public** key from SSM (`data.aws_ssm_parameter`). It holds NO 1Password items and intentionally has NO `onepassword` provider.

**`tofu/compute/`** — the bulk of the infrastructure, composed from `modules/`:

| Concern | Purpose |
|---------|---------|
| providers | Proxmox (bpg/proxmox v0.93.0), 1Password (~3.0), Ansible (~1.3.0) providers |
| backend | S3 + SSE-KMS remote state backend |
| variables | `vm_configs`, `postgresql_lxc_config`, `postgresql_databases`, `disabled_workloads`, `onepassword_vault_id` |
| ubuntu template | VM template (ID 1000) from Ubuntu Noble cloud image |
| cloud-init | Standard cloud-init (user_data + vendor_data) |
| cloud-init (gitlab) | Enhanced cloud-init for GitLab (postfix, ufw, etc.) |
| qemu VMs | VMs via `for_each` from `vm_configs`; 10 clone retries; per-VM datastore support |
| lxc debian template | Downloads Debian 12 LXC template |
| lxc postgresql | PostgreSQL LXC container definition |
| ssh keys | Fleet Ansible SSH key **read** from 1Password via Connect (`ssh-keys.tf` is a `data` source, not a `tls_private_key` resource) |
| ansible inventory | Dynamic inventory via OpenTofu Ansible provider |
| outputs | Infrastructure summary, URLs, 1Password item IDs |

> The patched UniFi provider rationale is documented separately in `tofu/PATCHED-PROVIDER.md`.

**Proxmox Connection**:
- API: https://192.168.40.206:8006 (primary for most operations)
- SSH: User `terraform` via SSH agent (for file operations like template creation)

**Datastores**:
- `nas-infrastructure`: Cloud images, cloud-init snippets, LXC templates
- `vm-data`: VM/LXC disks (NFS, default for most VMs)
- `local-zfs`: ZFS pool on nvme1n1 (NVMe SSD) for performance-tier VMs (Immich)
- `local-lvm`: LVM-thin on nvme0n1 (338GB available, future PostgreSQL migration target)

## Ansible Structure

Files in `ansible/`:

| Path | Purpose |
|------|---------|
| `ansible.cfg` | Dynamic inventory, SSH config, fact caching |
| `requirements.yml` | `onepassword.connect >=2.3.0`, `community.general` |
| `inventory/terraform.yml` | Dynamic inventory plugin (reads OpenTofu state from `../tofu/compute`; filename retained for the inventory plugin) |
| `inventory/group_vars/all.yml` | Global: timezone, DNS, NTP, firewall |
| `inventory/group_vars/postgresql.yml` | PostgreSQL tuning, HBA rules |
| `inventory/host_vars/postgresql.yml` | Database definitions, firewall rules |
| `inventory/host_vars/gitlab.yml` | GitLab domain, memory settings, HTTPS config |
| `inventory/host_vars/immich.yml` | Immich domain, NFS config, feature flags |
| `inventory/host_vars/mealie.yml` | Mealie backup client config |
| `inventory/host_vars/runitup.yml` | Run It Up backup client config |
| `inventory/host_vars/tandoor.yml` | Tandoor backup client config |
| `inventory/group_vars/vault.yml` | Encrypted fallback secrets (Ansible Vault) |

**Roles**:
- `ssh-key-loader/`: Retrieves SSH key from 1Password Connect for playbook authentication
- `certificates/`: Retrieves certs from 1Password, installs CA to trust store, deploys server cert/key
- `postgresql/`: Installs PostgreSQL 15, creates databases/users, configures pg_hba.conf
- `gitlab/`: Installs GitLab CE Omnibus, configures gitlab.rb with memory-constrained settings
- `mealie/`: Mealie recipe management with Docker Compose + nginx SSL
- `runitup/`: "Run It Up" savings-tracker PWA — Docker (build from synced repo), nginx SSL, SQLite (no external DB)
- `tandoor/`: Tandoor Recipes with Docker Compose + nginx SSL
- `immich/`: Immich photo management — Docker, NFS mount, compose, nginx SSL, health checks

**Playbooks**:
- `site.yml`: Main orchestration (bootstrap, common, postgresql, gitlab, mealie, tandoor, immich)
- `bootstrap.yml`: LXC container prerequisite installation (python3, sudo via raw module)
- `common.yml`: Certificate deployment
- `postgresql.yml`: Database server configuration
- `gitlab.yml`: GitLab installation and configuration
- `immich.yml`: Immich photo management deployment

**Inventory Groups**:
- `postgresql`: LXC containers (root SSH access)
- `application_servers`: QEMU VMs (ansible user, NOPASSWD sudo)
- `homelab`: Meta-group containing all

## Common Commands

### OpenTofu (three states, applied in dependency order)

Apply the states in order: `network` → `opconnect` → `compute`. Each is its own root with an S3 + SSE-KMS backend, so `init`/`plan`/`apply` run from inside each state directory.

```bash
# State 1: network (foundation)
(cd tofu/network   && tofu init && tofu plan && tofu apply)
# State 2: opconnect (1Password items / secrets)
(cd tofu/opconnect && tofu init && tofu plan && tofu apply)
# State 3: compute (VMs, LXC, inventory, outputs)
(cd tofu/compute   && tofu init && tofu plan && tofu apply)

# Read outputs (compute state owns the infra summary, URLs, connection info)
(cd tofu/compute && tofu output infrastructure_summary)   # View all resources
(cd tofu/compute && tofu output gitlab_url)                # Get GitLab URL
(cd tofu/compute && tofu output postgresql_connection)     # Get PostgreSQL connection info

# Tear down a single DISPOSABLE app workload (mealie shown — gitlab CANNOT be targeted, see below)
(cd tofu/compute && tofu destroy -target='module.mealie[0].proxmox_virtual_environment_vm.disposable')
# Preferred escape hatch: disable a workload declaratively, then apply
#   set disabled_workloads = ["mealie"] in compute vars, then:
(cd tofu/compute && tofu apply)
```

> **`gitlab` is a `prevent_destroy` protected singleton** — it cannot be the destroy/`-target` example and is intentionally excluded from `disabled_workloads`. Use a disposable app workload (e.g. `mealie`) for any teardown demonstration.

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
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password authentication | OpenTofu |
| `TF_VAR_onepassword_vault_id` | 1Password vault UUID | OpenTofu, Ansible |
| `PROXMOX_VE_API_TOKEN` | Proxmox API authentication | OpenTofu |
| `SSH_AUTH_SOCK` | SSH agent socket (auto-set) | OpenTofu SSH operations |

## Resource Dependencies

```
Ubuntu Template (ID 1000)              Standard Debian 12 Template
    ↓                                  (downloaded from Proxmox)
GitLab VM (ID 1103) ──────────────┐         ↓
Mealie VM (ID 1104) ──────────────┤    PostgreSQL LXC (ID 2001)
Tandoor VM (ID 1105) ─────────────┤         │
Immich VM (ID 1106) ──────────────┤         │
Run It Up VM (ID 1111) ───────────┤         │
                                  ↓         │
                            Ansible playbooks
                            (bootstrap → common → apps)
```

## Adding New Infrastructure

**Add VM**: Update `vm_configs` → `(cd tofu/compute && tofu apply)` → `ansible-playbook playbooks/site.yml` _(content accuracy for IDs/authorship tracked separately)_

**Add Database**: Update `postgresql_databases` → Update `host_vars/postgresql.yml` → `(cd tofu/compute && tofu apply)` → `ansible-playbook playbooks/postgresql.yml` _(content accuracy for IDs/authorship tracked separately)_

**Add Ansible Role**: Create `roles/<name>/` with tasks, handlers, templates → Include in playbook → Run playbook

## 1Password Items Created by OpenTofu

| Item | Type | Contents |
|------|------|----------|
| Infrastructure Ansible SSH Key | Secure Note | ED25519 private/public key pair |
| PostgreSQL Admin (postgres) | Database | postgres user credentials |
| PostgreSQL - Mealie Database User | Database | mealie user credentials |
| PostgreSQL - Tandoor Database User | Database | tandoor user credentials |
| GitLab Root User | Login | root username, 32-char password |
| GitLab Runner Registration Token | Password | 32-char alphanumeric token |
| Tandoor Secret Key | Password | 50-char Django SECRET_KEY |
| Immich Database Password | Password | 32-char alphanumeric database credential |

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
1. OpenTofu creates LXC from standard Debian 12 template
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

There are two distinct SSH key paths.

### PATH A — Fleet key (1Password Connect)

The fleet Ansible key lives in 1Password and is **read** via Connect — OpenTofu never generates it. `compute/ssh-keys.tf` is a `data` source, never a `tls_private_key` resource.

1. The fleet ED25519 key is stored in 1Password as "Infrastructure Ansible SSH Key"
2. **OpenTofu** (`compute/ssh-keys.tf`) reads the public key from 1Password via Connect (a `data` source) to seed cloud-init `authorized_keys`
3. **Ansible** cleans any leftover temp key from previous runs (clean-before-load)
4. **Ansible** retrieves the key from 1Password Connect via the `ssh-key-loader` role
5. **Ansible** writes key to temp file (`/tmp/.ansible_ssh_key`) with 0600 permissions
6. **Ansible** cleans up temp file after playbook completion

### PATH B — opconnect bootstrap key (Direction A)

The opconnect bootstrap key is a **dedicated** key, generated **locally** by the seed playbook (`ansible/playbooks/opconnect_credentials.yml`) — OpenTofu does NOT generate it and stores no `tls_private_key` in state.

1. The **seed** (`opconnect_credentials.yml`) generates a dedicated Ed25519 key locally
2. The **private** key is stored in the AWS Secrets Manager bootstrap bundle
3. The **public** key is published to SSM (`/tmpx/onprem/opconnect/ansible_public_key`)
4. **OpenTofu** (`tofu/opconnect/`) reads ONLY the public key from SSM via `data.aws_ssm_parameter` — no `tls_private_key` resource, no private key in state

**Clean-Before-Load Pattern**:
Similar to Jenkins `deleteDir()` at pipeline start, the `ssh-key-loader` role removes any existing temp key before loading a fresh one. This ensures failed runs don't leave stale keys and the next run always starts with a clean workspace.

**Why 1Password Connect (not SSH agent)**:
- 1Password OpenTofu provider only supports `secure_note` category (not `SSH_KEY`)
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
- **State remote and encrypted**: per-state files live in the S3 backend with SSE-KMS encryption at rest (not committed to git)
- **SSH keys from GitHub**: Imported from user `thisisbramiller`
