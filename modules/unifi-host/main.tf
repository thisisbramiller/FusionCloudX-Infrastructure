# Per-host UniFi networking: DHCP fixed-IP reservation (observe-then-pin) + a
# local DNS A record. Extracted from the flat terraform/dns.tf per-VM resources.
#
# Strategy: observe-then-pin. The controller auto-creates each client when first
# seen on the network; allow_existing = true adopts that entry (no import). The
# ip is sourced from the live DHCP-assigned address (passed in by the caller).
# OPERATIONAL REQUIREMENT: the source guest must be RUNNING with a DHCP lease at
# plan/apply time, or its ip is null and the reservation errors.

resource "unifi_client" "this" {
  # lower(): bpg reports MACs upper-case; the UniFi controller stores them
  # lower-case and allow_existing adoption matches case-sensitively (the
  # provider returns "not found" otherwise).
  mac      = lower(var.mac)
  fixed_ip = var.ip
  name     = var.name

  # network_id is OMITTED by default (null). The flat dns.tf never set it: the
  # 0.41.x/0.42.x unifi_client cannot round-trip network_id (reads back null →
  # "inconsistent result after apply") and UniFi scopes the reservation by the
  # client's live network automatically. Setting it (non-null) is opt-in.
  network_id = var.network_id

  # Adopt the controller-auto-created client (observe-then-pin); no import.
  allow_existing = true
}

# Local DNS A record on the UDM Pro. record_type = "A" is set explicitly
# (schema-optional but operationally required; the UDM returns HTTP 500 without
# it). unifi_client.local_dns_record is intentionally NEVER set — a Device-DNS
# entry would overlap this static record and the controller rejects it (HTTP 400).
resource "unifi_dns_record" "this" {
  name        = "${var.name}.fusioncloudx.home"
  value       = var.ip
  record_type = "A"
  enabled     = true
}
