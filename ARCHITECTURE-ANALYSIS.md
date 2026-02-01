# Infrastructure Architecture Analysis: Monorepo vs Multi-Repo

**Date**: 2026-02-01
**Purpose**: Deep analysis of current infrastructure architecture to inform decision about repository structure
**Status**: Analysis Complete - Decision Pending

---

## Executive Summary

After deep repository analysis, the current **monorepo architecture is well-suited for the FusionCloudX homelab infrastructure**. The repository demonstrates sophisticated use of Terraform's `for_each` patterns and Ansible's role-based orchestration, with minimal cross-service dependencies that would benefit from separation.

**Recommendation**: **Keep monorepo**, with optional future extraction of semaphore-config to separate repo if Terraform provider for Semaphore is adopted.

---

## Current Architecture Analysis

### 1. Repository Structure

```
FusionCloudX-Infrastructure/
├── terraform/                    # Infrastructure provisioning
│   ├── backend.tf               # Local state (single file)
│   ├── provider.tf              # Proxmox + 1Password providers
│   ├── variables.tf             # Map-based VM configs, database lists
│   ├── ubuntu-template.tf       # Base template (ID 1000)
│   ├── cloud-init.tf            # User_data (per-VM) + vendor_data (shared/enhanced)
│   ├── cloud-init-gitlab.tf     # GitLab-specific vendor_data
│   ├── qemu-vm.tf               # for_each VM provisioning
│   ├── lxc-postgresql.tf        # Single PostgreSQL LXC + 1Password items
│   └── outputs.tf               # Structured outputs for Ansible
├── ansible/
│   ├── inventory/hosts.ini      # Manually updated from Terraform outputs
│   ├── playbooks/
│   │   ├── site.yml             # Orchestration (imports other playbooks)
│   │   ├── postgresql.yml       # PostgreSQL deployment
│   │   ├── gitlab.yml           # GitLab deployment
│   │   └── semaphore.yml        # Semaphore control plane
│   └── roles/
│       ├── postgresql/          # PostgreSQL installation + configuration
│       ├── gitlab/              # GitLab CE Omnibus installation
│       └── semaphore-controller/# Control plane setup
└── scripts/
    ├── update-inventory.sh      # Terraform → Ansible data transfer
    └── bootstrap-control-plane.sh
```

### 2. Key Architectural Patterns

#### **Terraform: Variable-Driven Infrastructure**

**Pattern**: Map-based `for_each` with shared resources
```hcl
variable "vm_configs" {
  type = map(object({
    vm_id = number
    name = string
    memory_mb = number
    cpu_cores = number
  }))

  default = {
    "semaphore-ui" = { vm_id = 1102, name = "semaphore-ui", ... }
    "gitlab" = { vm_id = 1103, name = "gitlab", ... }
  }
}

resource "proxmox_virtual_environment_vm" "qemu-vm" {
  for_each = var.vm_configs
  vm_id = each.value.vm_id
  name = each.value.name
  # Single resource definition creates multiple VMs
}
```

**Power**: Add new VM by adding one map entry - template application, cloud-init, networking all automatic.

#### **Cloud-Init: Split Configuration Pattern**

**Pattern**: Per-VM user_data + shared/enhanced vendor_data
- **User_data** (`for_each` loop): Hostname, users, SSH keys (per-VM)
- **Standard vendor_data** (shared): qemu-guest-agent, python3, pip
- **Enhanced vendor_data** (VM-specific):
  - `semaphore-ui`: ansible, terraform, git, build-essential
  - `gitlab`: curl, postfix, ufw

```hcl
initialization {
  user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config[each.key].id
  vendor_data_file_id = each.key == "semaphore-ui" ?
    proxmox_virtual_environment_file.semaphore_vendor_data_cloud_config.id :
    (each.key == "gitlab" ?
      proxmox_virtual_environment_file.gitlab_vendor_data_cloud_config.id :
      proxmox_virtual_environment_file.vendor_data_cloud_config.id)
}
```

**Power**: Reusable base configuration with service-specific enhancements.

#### **1Password Integration: Terraform Creates, Ansible Retrieves**

**Pattern**: Terraform provisions infrastructure + secrets, Ansible consumes
```hcl
# Terraform: Create 1Password item with generated password
resource "onepassword_item" "semaphore_db_user" {
  vault = var.onepassword_vault_id
  title = "PostgreSQL - Semaphore Database User"
  username = "semaphore"
  password_recipe {
    length = 32
    symbols = true
  }
}
```

```yaml
# Ansible: Retrieve password from 1Password Connect
- name: Retrieve Semaphore database password
  onepassword.connect.field_info:
    token: "{{ connect_token }}"
    item: "PostgreSQL - Semaphore Database User"
    field: "password"
    vault: "{{ vault_id }}"
  delegate_to: localhost
  register: semaphore_db_password_result
```

**Power**: Secrets generated once by Terraform, retrieved unlimited times by Ansible (no OP CLI dependency on managed hosts).

#### **PostgreSQL: Shared Resource Pattern**

**Pattern**: Single PostgreSQL LXC hosts multiple databases
```hcl
# Terraform: One LXC, multiple 1Password items
resource "proxmox_virtual_environment_container" "postgresql" {
  vm_id = 2001
  # Single container
}

resource "onepassword_item" "semaphore_db_user" { ... }
resource "onepassword_item" "wazuh_db_user" { ... }
```

```yaml
# Ansible: One role, variable-driven databases
postgresql_databases:
  - { name: "semaphore", owner: "semaphore" }
  - { name: "wazuh", owner: "wazuh" }
```

**Power**: Add new database by adding one variable entry in two places (terraform/variables.tf, ansible/host_vars/postgresql.yml).

#### **Ansible: Role-Based Orchestration**

**Pattern**: site.yml imports service-specific playbooks
```yaml
# site.yml
- name: Deploy PostgreSQL Database Server
  import_playbook: postgresql.yml
  tags: ['postgresql', 'databases']

- name: Deploy GitLab
  import_playbook: gitlab.yml
  tags: ['gitlab', 'applications']

- name: Deploy Semaphore Control Plane
  import_playbook: semaphore.yml
  tags: ['semaphore', 'control-plane']
```

**Power**: Run all services (`ansible-playbook site.yml`) or one service (`--tags gitlab`).

### 3. Data Flows and Dependencies

#### **Terraform → Ansible Data Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│ Terraform State (terraform.tfstate)                             │
│ - VM IPs (from QEMU guest agent)                                │
│ - LXC IPs (from DHCP)                                           │
│ - Database list                                                 │
│ - 1Password item IDs                                            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Terraform Outputs (JSON)                                        │
│ - vm_ipv4_addresses: { "semaphore-ui": "192.168.40.68", ... }  │
│ - ansible_inventory_postgresql: { hostname, ip, databases }     │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ ./ansible/update-inventory.sh
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Ansible Inventory (hosts.ini)                                   │
│ [postgresql]                                                    │
│ postgresql ansible_host=192.168.40.121                          │
│ [application_servers]                                           │
│ semaphore-ui ansible_host=192.168.40.68                         │
│ gitlab ansible_host=192.168.40.74                               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Ansible Playbooks Execute                                       │
│ - Roles access inventory variables (ansible_host)               │
│ - Fetch secrets from 1Password Connect                          │
│ - Configure services                                            │
└─────────────────────────────────────────────────────────────────┘
```

**Critical Dependency**: `update-inventory.sh` script bridges Terraform outputs to Ansible inventory. Manual step (semi-automated).

#### **Service Dependencies**

```
┌──────────────────────────────────────────────────────────────┐
│ Infrastructure Layer (Terraform)                             │
│ ┌────────────┐  ┌─────────────┐  ┌──────────┐              │
│ │ VM Template│  │ PostgreSQL  │  │  VMs     │              │
│ │  (ID 1000) │  │  LXC (2001) │  │ 1102-1103│              │
│ └──────┬─────┘  └──────┬──────┘  └────┬─────┘              │
│        │               │              │                     │
│        └───────────────┴──────────────┘                     │
│                        │                                    │
│                        ▼                                    │
│              ┌──────────────────────┐                       │
│              │  1Password Items     │                       │
│              │  (DB passwords)      │                       │
│              └──────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│ Configuration Layer (Ansible)                                │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│ │  PostgreSQL  │  │  GitLab      │  │  Semaphore   │       │
│ │  Role        │  │  Role        │  │  Role        │       │
│ └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│        │                 │                 │                │
└────────┼─────────────────┼─────────────────┼────────────────┘
         │                 │                 │
         ▼                 ▼                 ▼
    Databases         Embedded          Connects to
    Created           PostgreSQL        PostgreSQL LXC
```

**Key Finding**: Services are **operationally independent** after provisioning:
- **GitLab**: Uses embedded PostgreSQL (managed by Omnibus), no dependency on PostgreSQL LXC
- **Semaphore**: Connects to PostgreSQL LXC for its database
- **PostgreSQL LXC**: Provides databases for Semaphore, Wazuh (future)

**Cross-Service Communication**:
- Minimal: Semaphore → PostgreSQL (database connection)
- No Ansible cross-host orchestration (no `hostvars[other_host]` references)
- Each service playbook operates independently

### 4. State Management

**Current**: Local backend
```hcl
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

**Implications**:
- ✅ Simple: No remote backend setup required
- ✅ Fast: Local file access
- ❌ No locking: Concurrent `terraform apply` will corrupt state
- ❌ No collaboration: Multiple people can't work simultaneously
- ❌ Not suitable for multi-repo: Each repo would need separate state

**For Multi-Repo**: Would require migrating to remote backend (S3, Terraform Cloud, etc.)

---

## Monorepo Strengths (Current Architecture)

### 1. **Atomic Infrastructure Changes**

**Single commit** can modify:
- Terraform configuration (add new VM)
- Ansible role (configure new VM)
- Documentation (update architecture docs)
- Scripts (update inventory script)

**Example**: Adding new application VM
```bash
# Single PR with 4 file changes
terraform/variables.tf              # Add VM to vm_configs
ansible/inventory/hosts.ini         # Add to [application_servers]
ansible/playbooks/site.yml          # Add import_playbook
ansible/roles/new-app/              # Create role
```

**Multi-Repo**: Would require 2-3 separate PRs, coordinated deployment order.

### 2. **Shared Terraform State = Cross-Resource References**

**Current Power**: Resources can reference each other
```hcl
# VMs depend on template
resource "proxmox_virtual_environment_vm" "qemu-vm" {
  for_each = var.vm_configs
  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu-template.vm_id
  }
}

# PostgreSQL databases reference VM configs
variable "postgresql_databases" {
  # Knows about semaphore, wazuh from single source of truth
}
```

**Multi-Repo**: Separate states = no cross-references, must use `terraform_remote_state` data sources.

### 3. **Simplified Secrets Management**

**Single 1Password Vault**:
- All database passwords in one vault
- Terraform creates all items in single apply
- Ansible roles know item naming convention

**Multi-Repo**: Would need vault-per-service or complex naming conventions.

### 4. **Unified Dependency Graph**

**Terraform Dependency Example**:
```hcl
# VMs depend on template
depends_on = [proxmox_virtual_environment_vm.ubuntu-template]

# Cloud-init depends on files
initialization {
  user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id
}
```

**Terraform automatically knows**:
1. Create template first
2. Upload cloud-init files
3. Clone VMs
4. Create 1Password items

**Multi-Repo**: Manual coordination of deployment order across repos.

### 5. **Single Source of Truth for Infrastructure**

**Current Variables**:
```hcl
# terraform/variables.tf - ALL infrastructure defined here
variable "vm_configs" { ... }
variable "postgresql_lxc_config" { ... }
variable "postgresql_databases" { ... }
variable "onepassword_vault_id" { ... }
```

**Benefits**:
- See entire infrastructure in one file
- Understand relationships at a glance
- Avoid configuration drift between repos

### 6. **Consistent Tooling and CI/CD**

**Single repo** = single CI/CD pipeline:
- One GitHub Actions workflow
- One set of secrets (1Password token, Proxmox credentials)
- One deployment process
- One documentation structure

**Multi-Repo**: Each repo needs separate CI/CD, secrets, documentation.

---

## Multi-Repo Architecture Options

### Option A: Service-Based Separation

```
fusioncloudx-infrastructure/          # Base infrastructure
├── terraform/
│   ├── network.tf                    # Network configuration
│   ├── template.tf                   # VM templates
│   └── storage.tf                    # Storage pools
└── ansible/
    └── roles/common/                 # Shared roles

fusioncloudx-postgresql/              # Database service
├── terraform/
│   └── lxc-postgresql.tf
└── ansible/
    └── roles/postgresql/

fusioncloudx-gitlab/                  # GitLab service
├── terraform/
│   └── vm-gitlab.tf
└── ansible/
    └── roles/gitlab/

fusioncloudx-semaphore/               # Control plane
├── terraform/
│   └── vm-semaphore.tf
└── ansible/
    └── roles/semaphore-controller/
```

**Dependencies**:
- All service repos depend on infrastructure repo
- Semaphore depends on PostgreSQL (database connection)
- Deployment order: infrastructure → postgresql → services

### Option B: Layer-Based Separation

```
fusioncloudx-terraform/               # All infrastructure provisioning
├── network/
├── compute/
│   ├── templates.tf
│   ├── vms.tf
│   └── lxc.tf
└── secrets/
    └── 1password.tf

fusioncloudx-ansible/                 # All configuration management
├── playbooks/
├── roles/
└── inventory/

fusioncloudx-semaphore-config/        # Semaphore-specific (using Terraform provider)
└── terraform/
    └── semaphore.tf                  # Projects, templates, key store
```

**Dependencies**:
- Ansible depends on Terraform (needs IPs)
- Semaphore-config depends on both (needs infrastructure + ansible setup)

### Option C: Control Plane Isolation

```
fusioncloudx-infrastructure/          # Everything except Semaphore (current minus semaphore)
└── (postgresql, gitlab, wazuh, etc.)

fusioncloudx-semaphore-config/        # Semaphore configuration as code
└── terraform/
    ├── provider.tf                   # semaphoreui/semaphore provider
    ├── projects.tf                   # Semaphore projects
    ├── repositories.tf               # Repository integrations
    ├── templates.tf                  # Task templates
    └── keys.tf                       # Key Store entries
```

**Purpose**: Avoid circular dependency where Semaphore manages the Terraform that configures itself.

---

## What Multi-Repo Would Unlock

### 1. **Independent Service Lifecycles**

**Benefit**: Deploy GitLab without affecting PostgreSQL
```bash
# Current monorepo
cd terraform/ && terraform apply    # Affects ALL resources
cd ansible/ && ansible-playbook site.yml  # Runs ALL playbooks

# Multi-repo
cd fusioncloudx-gitlab/terraform/ && terraform apply    # Only GitLab VM
cd fusioncloudx-gitlab/ansible/ && ansible-playbook gitlab.yml  # Only GitLab config
```

**But**: Already achievable with Terraform targeting and Ansible tags
```bash
# Current monorepo can do this too
terraform apply -target=proxmox_virtual_environment_vm.qemu-vm[\"gitlab\"]
ansible-playbook site.yml --tags gitlab
```

### 2. **Granular CI/CD Pipelines**

**Multi-Repo**:
- GitLab repo: CI pipeline only tests/deploys GitLab
- PostgreSQL repo: CI pipeline only tests/deploys PostgreSQL
- Faster CI (smaller scope), targeted deployments

**But**: Monorepo can achieve this with path-based triggers
```yaml
# .github/workflows/gitlab.yml
on:
  push:
    paths:
      - 'terraform/qemu-vm.tf'
      - 'ansible/roles/gitlab/**'
      - 'ansible/playbooks/gitlab.yml'
```

### 3. **Team Ownership Boundaries**

**Multi-Repo**: Assign repos to teams
- Database team owns `fusioncloudx-postgresql`
- Application team owns `fusioncloudx-gitlab`
- Platform team owns `fusioncloudx-infrastructure`

**But**: Single-person homelab doesn't benefit from this.

### 4. **Reduced Blast Radius**

**Multi-Repo**: Breaking change in GitLab repo can't affect PostgreSQL repo state.

**But**: Terraform `-target` and Ansible `--limit` provide same safety in monorepo.

### 5. **Semaphore Terraform Provider Adoption**

**Only valid unlock**: Separate `fusioncloudx-semaphore-config` repo would allow using Terraform provider for Semaphore without circular dependency.

**Use Case**: Manage Semaphore projects/templates/keys as code
```hcl
# fusioncloudx-semaphore-config/terraform/projects.tf
resource "semaphoreui_project" "infrastructure" {
  name = "FusionCloudX Infrastructure"
  repository = {
    url = "https://github.com/yourorg/fusioncloudx-infrastructure.git"
    ssh_key_id = semaphoreui_key_store.github_deploy.id
  }
}

resource "semaphoreui_template" "terraform_apply" {
  project_id = semaphoreui_project.infrastructure.id
  name = "Terraform Apply"
  playbook = "terraform/apply.sh"
}
```

**Current Limitation**: If Semaphore manages the Terraform that configures itself → bootstrap paradox.

---

## Trade-Offs Analysis

| Aspect | Monorepo | Multi-Repo |
|--------|----------|------------|
| **Atomic Changes** | ✅ Single commit affects multiple layers | ❌ Coordinated PRs across repos |
| **Cross-Resource References** | ✅ Direct Terraform references | ❌ Remote state data sources |
| **State Management** | ✅ Single local state (simple) | ❌ Remote state required (complexity) |
| **Dependency Visibility** | ✅ Explicit in single repo | ❌ Implicit across repos |
| **Deployment Complexity** | ✅ One deployment process | ❌ Multiple coordinated deployments |
| **CI/CD Setup** | ✅ Single pipeline | ❌ Pipeline per repo |
| **Secrets Management** | ✅ Unified 1Password vault | ⚠️ Per-repo or complex conventions |
| **Blast Radius** | ⚠️ Terraform apply affects all (but -target helps) | ✅ Changes isolated to repo |
| **Team Scaling** | ❌ Not suitable for large teams | ✅ Clear ownership boundaries |
| **Semaphore Provider** | ❌ Circular dependency | ✅ Separate semaphore-config possible |
| **Learning Curve** | ✅ All code in one place | ❌ Must navigate multiple repos |
| **Code Reuse** | ✅ Shared roles/modules in same repo | ❌ Git submodules or package registry |

---

## Specific Use Case: Current FusionCloudX Homelab

### Current Infrastructure

**VMs**:
- `semaphore-ui` (1102): Control plane, 8GB/8 cores
- `gitlab` (1103): Git + CI/CD, 16GB/8 cores

**LXCs**:
- `postgresql` (2001): Database server, 4GB/2 cores, hosts multiple databases

**Databases** (on postgresql LXC):
- `semaphore`: Semaphore UI database
- `wazuh`: Future SIEM database

**Planned Services**:
- Wazuh (SIEM)
- Teleport (access plane)
- Immich (photo management)
- Additional application VMs

### Multi-Repo Would Require

1. **Remote State Backend** (S3, Terraform Cloud, or Minio)
   - Setup complexity: Medium
   - Cost: $0-$50/month (Terraform Cloud free tier or self-hosted Minio)
   - Maintenance: Backup remote state, handle locking

2. **Cross-Repo Coordination** for changes like:
   - Adding new database to PostgreSQL → Update infrastructure repo + service repo
   - Changing network configuration → Update all service repos
   - Updating cloud-init → Update infrastructure repo + rebuild VMs in service repos

3. **Multiple CI/CD Pipelines**
   - Infrastructure repo: Terraform plan/apply for network, templates, storage
   - PostgreSQL repo: Terraform for LXC + Ansible for PostgreSQL
   - Each application repo: Terraform for VM + Ansible for app config
   - Coordination: How to ensure GitLab CI runs in correct order?

4. **Shared Code Distribution**
   - Common Ansible roles (fail2ban, monitoring agents, etc.)
   - Options: Git submodules (complex), Ansible Galaxy (publishing overhead), or duplicated code

### Monorepo Handles Well

1. **Adding New VM**: Single PR with 3 file changes
   ```
   terraform/variables.tf           # Add to vm_configs
   ansible/inventory/hosts.ini      # Add to group
   ansible/roles/new-service/       # Create role
   ```

2. **Updating PostgreSQL**: All dependent services in same repo
   ```
   terraform/lxc-postgresql.tf      # Update LXC specs
   ansible/roles/postgresql/        # Update config
   ansible/host_vars/postgresql.yml # Add new database
   ```

3. **Disaster Recovery**: Single `git clone` + `terraform apply` + `ansible-playbook site.yml`

4. **Control Plane Workflow**: Semaphore clones one repo, has all playbooks/terraform

---

## Recommendation: Keep Monorepo (with Optional Future Extension)

### Primary Recommendation: Maintain Current Monorepo

**Reasons**:

1. **Current Scale**: 2 VMs + 1 LXC + planned growth to ~5-10 services
   - Monorepo complexity is manageable
   - Multi-repo coordination overhead outweighs benefits

2. **Single Operator**: No team ownership boundaries needed
   - You understand entire stack
   - No need for per-repo access control

3. **Simplified State Management**: Local state sufficient for homelab
   - No need for remote backend complexity
   - Disaster recovery = single repo clone + apply

4. **Terraform Patterns Already Powerful**: `for_each` + variables = easy growth
   - Adding VMs: Map entry in variables.tf
   - Adding databases: List entry in postgresql_databases
   - No multi-repo coordination needed

5. **Ansible Already Modular**: Tags + imports provide isolation
   - `--tags postgresql` = only PostgreSQL changes
   - `--limit gitlab` = only GitLab host
   - No separate repos needed for this

6. **CI/CD Simplicity**: Single GitHub Actions workflow with path triggers
   - Already achieves targeted pipelines via `on.push.paths`
   - No coordination between repo pipelines needed

7. **No Circular Dependencies**: Not using Semaphore Terraform provider
   - Semaphore configured via UI (manual but acceptable)
   - No bootstrap paradox

### Optional Future Extension: Semaphore-Config Repo

**When**: If you decide to adopt Terraform provider for Semaphore (`semaphoreui/semaphore`)

**Structure**:
```
fusioncloudx-infrastructure/          # Main repo (current)
└── (all current content)

fusioncloudx-semaphore-config/        # New repo (Terraform-managed Semaphore)
├── terraform/
│   ├── provider.tf                   # semaphoreui/semaphore provider
│   ├── projects.tf                   # Semaphore projects as code
│   ├── repositories.tf               # Repository integrations
│   ├── templates.tf                  # Task templates
│   └── keys.tf                       # Key Store entries (SSH keys)
└── README.md
```

**Benefits**:
- Avoid circular dependency (Semaphore managing its own Terraform config)
- Version control Semaphore configuration
- GitOps for control plane

**Prerequisites**:
- Semaphore Terraform provider supports all needed resources (projects, templates, keys)
- Provider is stable and maintained
- Benefit of version-controlled Semaphore config outweighs manual UI setup

**Deployment Flow**:
1. `fusioncloudx-infrastructure`: Provision semaphore-ui VM + run Ansible to install Semaphore
2. `fusioncloudx-semaphore-config`: Configure Semaphore projects/templates via Terraform

---

## Action Items

### Immediate (Continue with Monorepo)

1. ✅ **No repository restructuring needed**
2. ✅ **Continue current development workflow**
3. ✅ **Leverage existing Terraform patterns** (for_each, variables)
4. ✅ **Use Ansible tags** for targeted deployments (`--tags service-name`)
5. ✅ **Maintain single documentation structure**

### Future Considerations (Re-evaluate at Scale)

**Trigger Points for Re-evaluation**:
- Infrastructure grows beyond 20-30 VMs/LXCs (monorepo becomes unwieldy)
- Multiple people collaborating (need ownership boundaries)
- Need for independent CI/CD per service (but try path-based triggers first)
- Adoption of Semaphore Terraform provider (extract semaphore-config repo)

**Decision Matrix**:
- **< 10 services**: Monorepo ✅
- **10-30 services**: Monorepo with strong tagging/modularization ✅
- **30+ services OR multi-team**: Consider multi-repo ⚠️

### Semaphore Provider Research

**Before extracting semaphore-config repo, verify**:
- Terraform provider maturity: https://registry.terraform.io/providers/semaphoreui/semaphore
- Supported resources: projects, templates, key_store, repositories, schedules
- Community adoption and issue tracker activity
- Does provider support Key Store (critical for SSH key management)?

---

## Conclusion

The current **monorepo architecture is the right choice** for FusionCloudX homelab infrastructure. The repository demonstrates sophisticated use of Terraform's `for_each` patterns and Ansible's orchestration, providing:

- **Atomic infrastructure changes** (single commit, single PR)
- **Simple state management** (local state, no coordination)
- **Clear dependency graph** (everything in one repo)
- **Fast iteration** (no cross-repo coordination)

**Multi-repo would add complexity** without providing meaningful benefits at current scale:
- Remote state backend required
- Coordinated deployments across repos
- Duplicated CI/CD setup
- Cross-repo dependency management

**The only valid reason to split** would be adopting Semaphore Terraform provider to avoid circular dependency - and that should be evaluated based on provider maturity, not repository structure philosophy.

**Recommendation**: **Keep monorepo, focus on infrastructure growth, re-evaluate at 30+ services or multi-team scenario.**
