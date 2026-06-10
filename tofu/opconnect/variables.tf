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
  description = "1Password Vault ID that holds the infrastructure credential items (read via the configured 1Password auth path — old Connect during the P4 cutover; SA token / op signin for a from-scratch rebuild). Provide via TF_VAR_onepassword_vault_id or a tfvars file."
}

variable "ansible_ssh_key_item_title" {
  type        = string
  default     = "Infrastructure Ansible SSH Key"
  description = "Title of the 1Password item holding the Ansible SSH key. Bootstrap-seeded BEFORE opconnect apply; read here as a data source via the configured 1Password auth path (old Connect during the P4 cutover; SA token / op signin for a rebuild) — the private key never enters TF state."
}

# ------------------------------------------------------------------------------
# DNS subdomain — temp-during-cutover, canonical-at-finalize (P4)
# ------------------------------------------------------------------------------
# The canonical name "opconnect" (opconnect.fusioncloudx.home) currently resolves
# to the OLD snowflake Connect (VM 100, 192.168.40.44). Creating the canonical
# A record for VM 1101 while the old one exists collides (the UDM rejects an
# overlapping record). The P4 cutover therefore BUILDS 1101 under a temp
# subdomain (apply with -var opconnect_dns_name=opconnect-new) — no collision —
# and reclaims the canonical name at FINALIZE (apply with the default, after the
# old record + VM 100 are retired). The old Connect stays reachable BY IP
# (192.168.40.44) the whole time, so consumers (OP_CONNECT_HOST) are unaffected.
# Only the unifi_dns_record name + the connect_host output follow this var; the
# VM's own hostname (cloud-init fqdn) stays canonical "opconnect".
variable "opconnect_dns_name" {
  type        = string
  default     = "opconnect"
  description = "Short DNS/UniFi-client name for the opconnect host (A record = <this>.fusioncloudx.home). Default 'opconnect' (canonical). During the P4 cutover, override to a temp value (e.g. 'opconnect-new') to avoid colliding with the old snowflake's opconnect->.44 record; flip back to the default at finalize."
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

variable "ansible_pubkey" {
  type        = string
  default     = ""
  description = "Optional Ansible SSH PUBLIC key supplied directly (e.g. via `op read` at apply) for a Connect-less rebuild. When set, the onepassword data-source read is skipped (count=0) so apply needs no live Connect. Default empty = read from 1Password via the provider (normal path)."
}
