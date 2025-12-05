output "vm_ipv4_addresses" {
  value = {
    for key, vm in proxmox_virtual_environment_vm.qemu-vm :
    key => try(vm.ipv4_addresses[1][0], "IP not available")
  }
  description = "VM IPv4 addresses from QEMU guest agent (map of VM name to IP)"
}
