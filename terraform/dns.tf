# ==============================================================================
# UniFi DNS & DHCP Reservations - FusionCloudX Infrastructure
# ==============================================================================
# Pins DHCP fixed-IP reservations and publishes local A records on the UDM Pro
# controller (VLAN 40 "Home Lab") for every QEMU VM and the PostgreSQL LXC.
#
# Strategy: observe-then-pin. The controller auto-creates each client when it
# is first seen on the network; unifi_client.allow_existing = true adopts that
# existing entry (no terraform import required). The fixed_ip/value fields are
# sourced from the live DHCP-assigned address Proxmox reports for each guest:
#   - the 6 QEMU VMs via the guest agent: ipv4_addresses[1][0]
#   - the postgresql LXC via the Proxmox container interfaces API: ipv4["eth0"].
#     LXCs have NO guest agent -- Proxmox reads the IP from the container netns,
#     so the eth0 map is populated only while the container is running + leased.
# OPERATIONAL REQUIREMENT: the source guest must be RUNNING with a DHCP lease at
# plan/apply time, or its ipv4 map is empty and the pin errors ("Invalid index:
# the given key does not identify an element"). On a clean apply each guest is
# created + started before its reservation resolves; a guest left stopped (e.g.
# after a half-finished destroy) must be started first (pct start / qm start).
#
# NOTE: unifi_client.local_dns_record is intentionally NEVER set -- a Device-DNS
# entry would overlap the static unifi_dns_record below and the controller
# rejects the overlap with HTTP 400. DNS is handled exclusively by
# unifi_dns_record. record_type = "A" is set explicitly (schema-optional but
# operationally required; the UDM returns HTTP 500 without it).
#
# OPERATIONAL -- ubiquiti-community/unifi 0.41.25 has two quirks worth knowing:
#   1. MACs must be lower-cased (see lower() below) -- the controller stores them
#      lower-case and allow_existing matches case-sensitively ("not found" else).
#   2. If a unifi_client reservation ever fails with "inconsistent result after
#      apply (.fixed_ip null)", the controller's client record is stale (issue
#      #145 _id drift, e.g. after repeated partial applies). Fix: `terraform
#      destroy -target=unifi_client.<x>` to forget it, then re-apply -- a net-new
#      create round-trips cleanly where an adopt of a stale record does not.
#      Default parallelism is fine for clean applies (no -parallelism flag needed).
# ==============================================================================

locals {
  # The 6 QEMU VMs: gitlab, mealie, tandoor, immich, duplicati, backrest
  fcx_vms = toset(keys(var.vm_configs))

  # Resolve each host's live DHCP IP ONCE so its reservation and its DNS record
  # always pin the SAME address (PR #41 review: makes the shared source explicit
  # + DRYs the repeated expression). VMs: guest-agent ipv4_addresses[1][0];
  # LXC: container interfaces API ipv4["eth0"].
  vm_ip  = { for k in local.fcx_vms : k => proxmox_virtual_environment_vm.qemu-vm[k].ipv4_addresses[1][0] }
  lxc_ip = proxmox_virtual_environment_container.postgresql.ipv4["eth0"]
}

# ------------------------------------------------------------------------------
# DHCP Fixed-IP Reservations
# ------------------------------------------------------------------------------
# NOTE: network_id is intentionally OMITTED. UniFi scopes a fixed-IP reservation
# by the client's live network automatically (every existing physical reservation
# on this controller carries no network_id), and the ubiquiti-community/unifi
# 0.41.25 unifi_client resource cannot round-trip network_id -- it reads back
# null and Terraform aborts with "inconsistent result after apply".

resource "unifi_client" "vm" {
  for_each = local.fcx_vms

  # lower(): bpg reports MACs upper-case; the UniFi controller stores them
  # lower-case and allow_existing adoption matches case-sensitively (the
  # provider returns "not found" otherwise). Normalize so the existing
  # controller client is adopted instead of erroring.
  # Index [1] = the first real NIC ([0] is the bpg placeholder 00:00:.../127).
  # Assumes a SINGLE-NIC guest; a multi-NIC VM would need a per-host override.
  mac      = lower(proxmox_virtual_environment_vm.qemu-vm[each.key].mac_addresses[1])
  fixed_ip = local.vm_ip[each.key]
  name     = each.key

  # Adopt the controller-auto-created client (observe-then-pin); no import.
  allow_existing = true
}

resource "unifi_client" "lxc" {
  mac      = lower(proxmox_virtual_environment_container.postgresql.network_interface[0].mac_address)
  fixed_ip = local.lxc_ip
  name     = "postgresql"

  # Adopt the controller-auto-created client (observe-then-pin); no import.
  allow_existing = true
}

# ------------------------------------------------------------------------------
# Local DNS A Records - *.fusioncloudx.home
# ------------------------------------------------------------------------------

resource "unifi_dns_record" "vm" {
  for_each = local.fcx_vms

  name        = "${each.key}.fusioncloudx.home"
  value       = local.vm_ip[each.key]
  record_type = "A"
  enabled     = true
}

resource "unifi_dns_record" "lxc" {
  name        = "postgresql.fusioncloudx.home"
  value       = local.lxc_ip
  record_type = "A"
  enabled     = true
}
