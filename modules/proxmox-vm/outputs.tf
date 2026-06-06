# Outputs coalesce across the two count-gated VM resources (protected/disposable).
# Exactly one block has count=1 (selected by var.protected), so
# one(concat(protected[*].x, disposable[*].x)) yields that single resource's
# attribute — same scalar shape consumers had before the split.

output "id" {
  value       = one(concat(proxmox_virtual_environment_vm.protected[*].id, proxmox_virtual_environment_vm.disposable[*].id))
  description = "Proxmox resource ID of the VM."
}

output "vm_id" {
  value       = one(concat(proxmox_virtual_environment_vm.protected[*].vm_id, proxmox_virtual_environment_vm.disposable[*].vm_id))
  description = "Proxmox VMID."
}

output "name" {
  value       = one(concat(proxmox_virtual_environment_vm.protected[*].name, proxmox_virtual_environment_vm.disposable[*].name))
  description = "VM name."
}

# Index [1] = first real NIC ([0] is the bpg placeholder 00:00:.../127). Null
# until the guest agent reports a DHCP lease; consumers should settle first.
output "ipv4_address" {
  value       = try(one(concat(proxmox_virtual_environment_vm.protected[*].ipv4_addresses, proxmox_virtual_environment_vm.disposable[*].ipv4_addresses))[1][0], null)
  description = "First IPv4 address of the first real NIC (guest-agent sourced), or null if unavailable."
}

output "mac_address" {
  value       = try(one(concat(proxmox_virtual_environment_vm.protected[*].mac_addresses, proxmox_virtual_environment_vm.disposable[*].mac_addresses))[1], null)
  description = "MAC address of the first real NIC, or null if unavailable."
}
