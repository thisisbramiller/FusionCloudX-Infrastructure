resource "proxmox_virtual_environment_vm" "test_vm" {
  name      = "test-vm"
  node_name = "zero"
  started   = true
  on_boot   = false
  # machine   = "q35"
  reboot = true
  tags      = ["terraform", "ubuntu"]
  bios      = "seabios"

  clone {
    vm_id = 1000
    full  = true
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = 2048
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  # efi_disk {
  #   datastore_id      = "local"
  #   file_format       = "qcow2"
  #   type              = "4m"
  #   pre_enrolled_keys = true
  # }

  initialization {
    datastore_id = "vm-data"
    file_format  = "qcow2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

}

output "vm_ipv4_address" {
  value = proxmox_virtual_environment_vm.test_vm.ipv4_addresses[1][0]
}
