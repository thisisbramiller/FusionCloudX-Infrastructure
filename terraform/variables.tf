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
    vm_id      = number
    name       = string
    memory_mb  = number
    cpu_cores  = number
    started    = bool
    on_boot    = optional(bool, true)
    full_clone = optional(bool, true)
  }))

  default = {
    "gitlab" = {
      vm_id      = 1103
      name       = "gitlab"
      memory_mb  = 16384  # 16GB for installation (can reduce to 4GB after installation if needed)
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
  }
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

