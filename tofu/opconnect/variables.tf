# ==============================================================================
# opconnect state — input variables
# ==============================================================================

variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.40.206:8006/"
  description = "Proxmox VE API URL."
}

# ------------------------------------------------------------------------------
# DNS subdomain
# ------------------------------------------------------------------------------
# The old snowflake Connect (VM 100, opconnect->192.168.40.44) is destroyed, so the
# "opconnect" namespace is open and VM 1101 owns it. The temp-subdomain dance used
# during the P4 cutover (to avoid colliding with the old record) is obsolete. This
# var drives the unifi_dns_record name + the connect_host output; the VM's own
# hostname (cloud-init fqdn) is always canonical "opconnect".
variable "opconnect_dns_name" {
  type        = string
  default     = "opconnect"
  description = "Short DNS/UniFi-client name for the opconnect host (A record = <this>.fusioncloudx.home). Default 'opconnect' (canonical); the namespace is open (old snowflake destroyed)."
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

# Removed (spec #68 — Phase C):
#   - ansible_pubkey: opconnect no longer owns the keypair; the ansible PUBLIC key
#     comes from SSM (ssh-keys.tf -> local.ansible_ssh_public_key), published by the seed.
#   - onepassword_vault_id / ansible_ssh_key_item_title: only the retired Option-D
#     tls_private_key write-back used them. The dedicated key is now a 1Password
#     SSH-Key item (read by Ansible); no 1Password write from this state.
