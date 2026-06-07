# ==============================================================================
# opconnect state — outputs
# ==============================================================================
# Failure paths are NULL (footgun #3), never a truthy "IP not available" string.
# opconnect is a protected singleton — always built — but its ipv4_address is
# null until the guest agent reports a DHCP lease, so the ip-derived outputs are
# try()-guarded to null. The dns_name + connect_host are STABLE (name-derived,
# do not depend on a live lease).
# ==============================================================================

output "opconnect_ip" {
  description = "opconnect VM IPv4 address (null until the guest agent reports a DHCP lease)."
  value       = module.opconnect.ipv4_address
}

output "opconnect_vm_id" {
  description = "opconnect Proxmox VMID."
  value       = module.opconnect.vm_id
}

output "opconnect_dns_name" {
  description = "opconnect published A-record FQDN (follows var.opconnect_dns_name — temp during the P4 cutover, canonical at finalize)."
  value       = "${var.opconnect_dns_name}.fusioncloudx.home"
}

# ------------------------------------------------------------------------------
# Connect host URL — the downstream repoint target (P4 cutover)
# ------------------------------------------------------------------------------
# Stable, name-derived (NOT lease-derived): the on-prem 1Password provider + the
# ssh-key-loader role get repointed to OP_CONNECT_HOST=<this> at P4 once the new
# Connect server is verified serving a test secret. Port 8080 = connect-api
# (the official Connect compose publishes the API on 8080).
# ------------------------------------------------------------------------------

output "connect_host" {
  description = "1Password Connect API base URL for downstream OP_CONNECT_HOST repointing (P4 cutover target). Follows var.opconnect_dns_name — temp subdomain during the cutover, canonical at finalize."
  value       = "http://${var.opconnect_dns_name}.fusioncloudx.home:8080"
}
