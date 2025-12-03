variable "proxmox_api_url" {
  type        = string
  default     = "https://zero.fusioncloudx.home:8006/"
  description = "Proxmox VE API URL"
}

variable vm_configs {
  type = map(object({
    vm_id = number
    name = string
    memory_mb = number
    cpu_cores = number
    started = bool
    full_clone = optional(bool, false)
  }))

  default = {
    "teleport" = {
      vm_id     = 1101
      name      = "teleport"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
      full_clone = false
    }
    "ansible" = {
      vm_id     = 1102
      name      = "ansible"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
      full_clone = false
    }
    "wazuh" = {
      vm_id     = 1103
      name      = "wazuh"
      memory_mb = 4096
      cpu_cores = 2
      started   = true
      full_clone = false
    }
    "immich" = {
      vm_id     = 1104
      name      = "immich"
      memory_mb = 4096
      cpu_cores = 2
      started   = false
      full_clone = false
    }
  }
}