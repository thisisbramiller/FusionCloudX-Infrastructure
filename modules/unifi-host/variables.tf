variable "name" {
  type        = string
  description = "Host name. Used as the unifi_client name and the A-record short name (<name>.fusioncloudx.home)."
}

variable "mac" {
  type = string
  # nullable = false fails LOUD at the module boundary if a caller passes a null
  # mac_address (guest agent not yet reporting), with a clearly-named error
  # BEFORE the cryptic `lower(null)` crash in main.tf. Plan is unaffected:
  # unknown (computed) != null, so plan-time values pass; only a resolved null at
  # apply errors. Fail-loud is deliberate over a count-guard that would SILENTLY
  # skip the reservation/DNS, leaving a host with no record yet reporting success.
  nullable    = false
  description = "MAC address of the host's first real NIC. Lower-cased internally (the controller stores MACs lower-case and allow_existing matches case-sensitively). Must be non-null: the source guest must be up with its NIC reported at apply."
}

variable "ip" {
  type = string
  # See var.mac: nullable = false enforces the documented operational requirement
  # (source guest RUNNING with a DHCP lease at apply) declaratively and fails
  # loud with a named error rather than crashing on null deep in the resources.
  nullable    = false
  description = "Live DHCP-assigned IPv4 address to pin as the fixed-IP reservation and publish as the A record. Must be non-null: the source guest must have a DHCP lease (guest agent reporting) at apply."
}

variable "network_id" {
  type        = string
  default     = null
  description = "Optional UniFi network ID to scope the reservation. Default null = OMIT (the proven-working dns.tf omits it; ubiquiti-community/unifi cannot round-trip network_id on unifi_client and aborts with 'inconsistent result after apply')."
}
