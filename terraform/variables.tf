variable "proxmox_api_url" {
  type        = string
  default     = "https://zero.fusioncloudx.home:8006/"
  description = "Proxmox VE API URL"
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
    "teleport" = {
      vm_id      = 1101
      name       = "teleport"
      memory_mb  = 2048
      cpu_cores  = 2
      started    = true
      full_clone = true
    }
    "semaphore" = {
      vm_id      = 1102
      name       = "semaphore"
      memory_mb  = 2048
      cpu_cores  = 2
      started    = true
      full_clone = true
    }
    "wazuh" = {
      vm_id      = 1103
      name       = "wazuh"
      memory_mb  = 4096
      cpu_cores  = 2
      started    = true
      full_clone = true
    }
    "immich" = {
      vm_id      = 1104
      name       = "immich"
      memory_mb  = 4096
      cpu_cores  = 2
      started    = true
      full_clone = true
    }
    "pi-hole" = {
      vm_id      = 1105
      name       = "pi-hole"
      memory_mb  = 1024
      cpu_cores  = 1
      started    = true
      full_clone = true
    }
  }
}