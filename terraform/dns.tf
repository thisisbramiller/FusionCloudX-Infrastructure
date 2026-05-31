# ==============================================================================
# UniFi static DNS records for the FusionCloudX VM fleet (DNS-only).
# Provider: ubiquiti-community/unifi (see provider.tf). Validated on UDM Pro
# UniFi OS 5.1.12 / Network 10.3.58. record_type MUST be set ("A") — the UDM
# returns HTTP 500 if omitted (upstream issue #137).
#
# Migration (done before this applies): each VM's per-client Device DNS
# (local_dns_record) was cleared — keeping its fixed_ip reservation — so the
# static record has no overlap. Physical/non-Terraform devices (nzxt, nas,
# printer, pi, echo, zero, opconnect) intentionally STAY on Device DNS.
#
# NOTE: ui.fusioncloudx.home is the UniFi console's own record (192.168.254.1)
# — it is NOT a VM and is deliberately NOT managed here. Do not add it.
#
# Values are explicit (decoupled from the proxmox provider so a DNS apply needs
# no proxmox refresh). The fixed_ip reservations keep these stable. Future
# enhancement: source value from proxmox_virtual_environment_vm[*].ipv4_addresses
# once the full fleet (incl. runitup) lives in one module + MACs are pinned.
# ==============================================================================

locals {
  fcx_dns_records = {
    runitup    = "192.168.40.25"
    gitlab     = "192.168.40.220"
    mealie     = "192.168.40.167"
    tandoor    = "192.168.40.128"
    immich     = "192.168.40.85"
    duplicati  = "192.168.40.180"
    backrest   = "192.168.40.204"
    postgresql = "192.168.40.251"
  }
}

resource "unifi_dns_record" "fcx" {
  for_each = local.fcx_dns_records

  name        = "${each.key}.fusioncloudx.home"
  value       = each.value
  record_type = "A"
  enabled     = true
}

output "fcx_dns_records" {
  description = "FusionCloudX static DNS records managed in UniFi"
  value       = { for k, r in unifi_dns_record.fcx : r.name => r.value }
}
