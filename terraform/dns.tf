# ==============================================================================
# UniFi static DNS records for the FusionCloudX VM fleet (DNS-only).
# Provider: ubiquiti-community/unifi (see provider.tf). Validated on UDM Pro
# UniFi OS 5.1.12 / Network 10.3.58. record_type MUST be set ("A") — the UDM
# returns HTTP 500 if it is omitted (upstream issue #137).
#
# Phase 1 (runitup-first POC): ONLY runitup — the one fleet VM with no existing
# per-client Device DNS record, so the static create has no overlap.
#
# Phase 2 (fleet rollout, follow-up): uncomment the rest AFTER clearing each
# client's local_dns_record (keep fixed_ip). Once the VM resources live in this
# module, switch `value` to proxmox_virtual_environment_vm.qemu-vm[<k>].ipv4_addresses[1][0]
# so the record follows the VM on rebuild.
# ==============================================================================

locals {
  fcx_dns_records = {
    runitup = "192.168.40.25"
    # --- Phase 2: pending per-client Device-DNS migration (clear local_dns_record, keep fixed_ip) ---
    # gitlab     = "192.168.40.220"
    # mealie     = "192.168.40.167"
    # tandoor    = "192.168.40.128"
    # immich     = "192.168.40.85"
    # duplicati  = "192.168.40.180"
    # backrest   = "192.168.40.204"
    # postgresql = "192.168.40.251"
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
