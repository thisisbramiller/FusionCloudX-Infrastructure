variable "name" {
  type        = string
  description = "Host name. Used as the unifi_client name and the A-record short name (<name>.fusioncloudx.home)."
}

variable "mac" {
  type        = string
  description = "MAC address of the host's first real NIC. Lower-cased internally (the controller stores MACs lower-case and allow_existing matches case-sensitively)."
}

variable "ip" {
  type        = string
  description = "Live DHCP-assigned IPv4 address to pin as the fixed-IP reservation and publish as the A record."
}

variable "network_id" {
  type        = string
  default     = null
  description = "Optional UniFi network ID to scope the reservation. Default null = OMIT (the proven-working dns.tf omits it; ubiquiti-community/unifi cannot round-trip network_id on unifi_client and aborts with 'inconsistent result after apply')."
}
