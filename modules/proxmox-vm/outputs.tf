output "id" {
  value       = proxmox_virtual_environment_vm.this.id
  description = "Proxmox resource ID of the VM."
}

output "vm_id" {
  value       = proxmox_virtual_environment_vm.this.vm_id
  description = "Proxmox VMID."
}

output "name" {
  value       = proxmox_virtual_environment_vm.this.name
  description = "VM name."
}

# Index [1] = first real NIC ([0] is the bpg placeholder 00:00:.../127). Null
# until the guest agent reports a DHCP lease; consumers should settle first.
output "ipv4_address" {
  value       = try(proxmox_virtual_environment_vm.this.ipv4_addresses[1][0], null)
  description = "First IPv4 address of the first real NIC (guest-agent sourced), or null if unavailable."
}

output "mac_address" {
  value       = try(proxmox_virtual_environment_vm.this.mac_addresses[1], null)
  description = "MAC address of the first real NIC, or null if unavailable."
}
