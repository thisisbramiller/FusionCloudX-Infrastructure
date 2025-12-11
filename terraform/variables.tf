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
    "semaphore-ui" = {
      vm_id      = 1102
      name       = "semaphore-ui"
      memory_mb  = 4096
      cpu_cores  = 2
      started    = true
      full_clone = true
    }
  }
}