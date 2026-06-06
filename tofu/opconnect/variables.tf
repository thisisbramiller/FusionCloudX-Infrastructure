# ==============================================================================
# opconnect state — input variables
# ==============================================================================

variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.40.206:8006/"
  description = "Proxmox VE API URL."
}

variable "onepassword_vault_id" {
  type        = string
  description = "1Password Vault ID that holds the infrastructure credential items (read via the SA token). Provide via TF_VAR_onepassword_vault_id or a tfvars file."
}

variable "ansible_ssh_key_item_title" {
  type        = string
  default     = "Infrastructure Ansible SSH Key"
  description = "Title of the 1Password item holding the Ansible SSH key. Bootstrap-seeded BEFORE opconnect apply; read here as a data source via the SA token — the private key never enters TF state."
}

# ------------------------------------------------------------------------------
# opconnect VM sizing
# ------------------------------------------------------------------------------

variable "opconnect_cores" {
  type        = number
  default     = 2
  description = "CPU cores for the opconnect VM (runs two lightweight 1Password Connect containers)."
}

variable "opconnect_memory_mb" {
  type        = number
  default     = 2048
  description = "Dedicated memory (MB) for the opconnect VM."
}
