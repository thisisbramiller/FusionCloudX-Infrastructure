# ==============================================================================
# compute state — input variables
# ==============================================================================

variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.40.206:8006/"
  description = "Proxmox VE API URL."
}

variable "onepassword_vault_id" {
  type        = string
  description = "1Password Vault ID that holds the infrastructure credential items. Provide via TF_VAR_onepassword_vault_id or a tfvars file."
}

# ==============================================================================
# Workload Toggles (dev escape hatch)
# ==============================================================================
# Build only the disposable workloads a given dev cycle needs. Each disposable
# service file (mealie/tandoor/immich/runitup) gates its modules on
# contains(var.disabled_workloads, "<svc>"). The protected singletons (gitlab,
# postgresql) are NOT gateable here — they are always built. The validation
# below restricts toggling to the disposable set so a disabled_workloads entry
# can never silently no-op against a protected singleton.
# ==============================================================================

variable "disabled_workloads" {
  type        = list(string)
  default     = []
  description = "Dev escape hatch: disposable service names to EXCLUDE from the build (e.g. [\"mealie\",\"tandoor\"])."

  validation {
    condition     = alltrue([for w in var.disabled_workloads : contains(["mealie", "tandoor", "immich", "runitup"], w)])
    error_message = "disabled_workloads may only contain disposable services: mealie, tandoor, immich, runitup. gitlab and postgresql are protected singletons and cannot be disabled."
  }
}

variable "ansible_ssh_key_item_title" {
  type        = string
  default     = "Infrastructure Ansible SSH Key"
  description = "Title of the 1Password item holding the Ansible SSH key. Bootstrap-seeded BEFORE compute apply (P5 dependency); read here as a data source — the private key never enters TF state."
}
