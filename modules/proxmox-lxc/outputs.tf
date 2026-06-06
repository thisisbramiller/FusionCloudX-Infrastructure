output "id" {
  value       = proxmox_virtual_environment_container.this.id
  description = "Proxmox resource ID of the container."
}

output "vm_id" {
  value       = proxmox_virtual_environment_container.this.vm_id
  description = "Proxmox VMID."
}

output "hostname" {
  value       = proxmox_virtual_environment_container.this.initialization[0].hostname
  description = "Container hostname."
}

# LXCs have no guest agent — Proxmox reads the IP from the container netns, so the
# eth0 map is populated only while the container is running + holds a DHCP lease.
# NOTE: this output is `ipv4` (NOT `ipv4_address` like the proxmox-vm module) —
# the LXC IP comes from the container netns eth0 map, a different attribute shape
# than the VM's guest-agent ipv4_addresses; consumers (postgresql.tf) use .ipv4.
output "ipv4" {
  value       = try(proxmox_virtual_environment_container.this.ipv4["eth0"], null)
  description = "IPv4 address on eth0, or null if unavailable."
}

output "mac_address" {
  value       = try(proxmox_virtual_environment_container.this.network_interface[0].mac_address, null)
  description = "MAC address of the eth0 interface, or null if unavailable."
}
