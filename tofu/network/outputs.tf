output "homelab_network_id" {
  value       = data.unifi_network.homelab.id
  description = "Stable UniFi network id of the VLAN-40 'Home Lab' network. Consumed by the compute state via terraform_remote_state (stable id only, never live IPs)."
}
