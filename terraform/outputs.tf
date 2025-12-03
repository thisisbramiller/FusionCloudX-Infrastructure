output "vm_ipv4_address" {
  value = try(
    proxmox_virtual_environment_vm.test_vm.ipv4_addresses[1][0],
    "IP address not available - ensure QEMU guest agent is running"
  )
  description = "VM IPv4 address from QEMU guest agent"
}
