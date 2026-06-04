variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.40.206:8006/"
  description = "Proxmox VE API URL"
}

variable "proxmox_ssh_host" {
  type        = string
  default     = "192.168.40.206"
  description = "Proxmox VE SSH host for template management and remote operations"
}

variable "vm_configs" {
  type = map(object({
    vm_id        = number
    name         = string
    memory_mb    = number
    cpu_cores    = number
    started      = bool
    on_boot      = optional(bool, true)
    full_clone   = optional(bool, true)
    datastore_id = optional(string, "vm-data")
  }))

  default = {
    "gitlab" = {
      vm_id      = 1103
      name       = "gitlab"
      memory_mb  = 16384 # 16GB for installation (can reduce to 4GB after installation if needed)
      cpu_cores  = 8     # 8 cores for faster installation (can reduce to 4 cores after installation if needed)
      started    = true
      full_clone = true
    }
    "mealie" = {
      vm_id     = 1104
      name      = "mealie"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
    "tandoor" = {
      vm_id     = 1105
      name      = "tandoor"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
    "immich" = {
      vm_id        = 1106
      name         = "immich"
      memory_mb    = 8192 # 8GB for ML processing (face recognition, CLIP search)
      cpu_cores    = 4
      started      = true
      datastore_id = "local-zfs" # NVMe SSD for database + Docker I/O performance
    }
    "duplicati" = {
      vm_id     = 1107
      name      = "duplicati"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
    "backrest" = {
      vm_id     = 1108
      name      = "backrest"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
  }
}

# ==============================================================================
# Workload Toggles (dev escape hatches)
# ==============================================================================
# Build only the workloads a given dev cycle needs. Two composable knobs feed
# local.enabled_vm_configs (the single source of truth: qemu-vm + cloud-init
# for_each, dns.tf fcx_vms; ansible-inventory follows qemu-vm; outputs are
# try()-guarded). Single-host app plays auto-skip when their host is absent, and
# the "Configure Backup Clients" role self-skips when backrest is absent.
#
#   - enable_backup_stack=false : drop the redundant app-level backup stack
#     (backrest + duplicati). Redundant in dev because the fleet is rebuilt
#     constantly (ephemeral data) and the UNAS Pro is backed up + snapshotted.
#     Saves ~19min of serial clone time; skips the known-incomplete backup-client
#     wiring. Flip to true for backup-strategy work.
#   - disabled_workloads=[...] : general escape hatch to drop any other VM(s),
#     e.g. ["gitlab"] to skip GitLab's ~18min clone during non-SCM dev.
#
# CAVEAT: only disable an APP (gitlab/mealie/tandoor/immich) while the backup
# stack is OFF. With backrest built, host_vars/backrest.yml dereferences
# hostvars[<app>] for its NFS source-mounts + backup hooks and would fail at
# template time. The robust fix (inventory-driven backrest mounts/hooks) is
# deferred to the backup-strategy work.
# ==============================================================================

variable "enable_backup_stack" {
  type        = bool
  default     = true
  description = "When false, exclude the app-level backup stack (local.backup_stack_members = backrest + duplicati) from the build. Use during dev; re-enable for backup-strategy work."
}

variable "disabled_workloads" {
  type        = list(string)
  default     = []
  description = "Dev escape hatch: vm_configs keys to EXCLUDE from the build (e.g. [\"gitlab\",\"mealie\"]). Composes with enable_backup_stack. Valid keys: gitlab, mealie, tandoor, immich, duplicati, backrest. Only disable an app while the backup stack is off (see Workload Toggles comment)."
}

# ==============================================================================
# PostgreSQL LXC Container Configuration
# ==============================================================================
# Single PostgreSQL container hosting multiple databases
# ==============================================================================

variable "postgresql_lxc_config" {
  type = object({
    vm_id       = number
    hostname    = string
    description = string
    memory_mb   = number
    cpu_cores   = number
    disk_gb     = number
    started     = bool
    on_boot     = optional(bool, true)
    tags        = optional(list(string), [])
  })

  description = "Configuration for single PostgreSQL LXC container (hosts multiple databases)"

  default = {
    vm_id       = 2001
    hostname    = "postgresql"
    description = "Centralized PostgreSQL database server for homelab services (semaphore, wazuh, etc.)"
    memory_mb   = 4096 # 4GB RAM for multiple databases
    cpu_cores   = 2
    disk_gb     = 64 # 64GB disk for multiple databases and growth
    started     = true
    on_boot     = true
    tags        = ["database", "postgresql", "homelab"]
  }
}

# ==============================================================================
# PostgreSQL Database Configurations
# ==============================================================================
# Defines which databases should be created on the PostgreSQL instance
# Ansible will use this configuration to create databases and users
# ==============================================================================

variable "postgresql_databases" {
  type = list(object({
    name        = string
    description = string
    owner       = string # Database owner (user)
  }))

  description = "List of databases to create on the PostgreSQL instance"

  default = [
    {
      name        = "wazuh"
      description = "Database for Wazuh (SIEM)"
      owner       = "wazuh"
    },
    {
      name        = "mealie"
      description = "Database for Mealie (Recipe Management)"
      owner       = "mealie"
    },
    {
      name        = "tandoor"
      description = "Database for Tandoor Recipes"
      owner       = "tandoor"
    }
  ]
}

# ==============================================================================
# 1Password Configuration
# ==============================================================================

variable "onepassword_vault_id" {
  type        = string
  description = "1Password Vault ID for storing database credentials"

  # This should be provided via environment variable or tfvars file:
  # export TF_VAR_onepassword_vault_id="your-vault-uuid"
  # OR: Create terraform.tfvars with: onepassword_vault_id = "your-vault-uuid"
}

