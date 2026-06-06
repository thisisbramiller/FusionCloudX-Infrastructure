# ==============================================================================
# THIN foundational network state — onprem/proxmox/network
# ==============================================================================
# Resolves the stable id of the VLAN-40 "Home Lab" network so the compute state
# can reference it (via terraform_remote_state) without hardcoding a controller
# _id. STABLE IDs ONLY — never live IPs.
#
# SCOPE LOCK (spec D9): this state is THIN. Full UDM fabric authoring — VLANs,
# firewall rules, WiFi/WLAN — is explicitly OUT OF SCOPE (a separate
# Network-as-Code / UDM-reflash effort). Per-VM unifi_client reservations + A
# records live in the compute state (modules/unifi-host), not here.
#
# Schema confirmed against ubiquiti-community/unifi 0.42.0 (the fork's base): the
# unifi_network data source accepts `name` (Optional) and exposes `id` (String).
# ==============================================================================

data "unifi_network" "homelab" {
  name = "Home Lab" # VLAN 40, 192.168.40.0/24
}
