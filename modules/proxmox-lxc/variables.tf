variable "vm_id" {
  type        = number
  description = "Proxmox VMID for the container."
}

variable "hostname" {
  type        = string
  description = "Container hostname."
}

variable "cores" {
  type        = number
  description = "Number of CPU cores."
}

variable "memory_mb" {
  type        = number
  description = "Dedicated memory in MB."
}

variable "disk_gb" {
  type        = number
  description = "Root disk size in GB."
}

variable "datastore_id" {
  type        = string
  default     = "local-zfs"
  description = "Datastore for the root disk. Greenfield storage lock: local-zfs (the flat config used vm-data)."
}

variable "template_file_id" {
  type        = string
  description = "Proxmox file ID of the LXC template (e.g. the downloaded Debian 12 vztmpl)."
}

variable "ssh_pubkey" {
  type        = string
  description = "SSH public key (OpenSSH format) injected for the container user account."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags applied to the container."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the container is started after creation."
}

variable "on_boot" {
  type        = bool
  default     = true
  description = "Whether the container starts on host boot."
}

variable "nesting" {
  type        = bool
  default     = true
  description = "Allow nested containers / Docker (features.nesting)."
}

variable "swap_mb" {
  type        = number
  default     = 512
  description = "Swap in MB."
}
