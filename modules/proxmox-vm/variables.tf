variable "vm_id" {
  type        = number
  description = "Proxmox VMID for the guest."
}

variable "name" {
  type        = string
  description = "VM name (also the Proxmox guest name)."
}

variable "cores" {
  type        = number
  description = "Number of CPU cores."
}

variable "memory_mb" {
  type        = number
  description = "Dedicated memory in MB."
}

variable "datastore_id" {
  type        = string
  default     = "local-zfs"
  description = "Datastore for the extra OS disk (scsi1). Greenfield storage lock: local-zfs (the flat config used vm-data)."
}

variable "template_vm_id" {
  type        = number
  default     = 9001
  description = "VMID of the template to full-clone from (Scheme B ubuntu-template = 9001)."
}

variable "user_data_file_id" {
  type        = string
  description = "Proxmox file ID of the cloud-init user-data snippet."
}

variable "vendor_data_file_id" {
  type        = string
  description = "Proxmox file ID of the cloud-init vendor-data snippet."
}

variable "tags" {
  type        = list(string)
  default     = ["opentofu", "ubuntu"]
  description = "Tags applied to the guest."
}

variable "started" {
  type        = bool
  default     = true
  description = "Whether the VM is started after creation."
}

variable "on_boot" {
  type        = bool
  default     = true
  description = "Whether the VM starts on host boot."
}

variable "extra_disk_size_gb" {
  type        = number
  default     = null
  description = "When set, attach an extra OS disk (scsi1) of this size on var.datastore_id. Null = no extra disk."
}
