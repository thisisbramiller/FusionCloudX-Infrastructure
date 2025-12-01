resource "proxmox_virtual_environment_vm" "test_vm" {
    name      = "test-vm"
    node_name = "zero"
    started   = true
    reboot    = true
    on_boot   = false
    machine   = "q35"
    tags      = ["terraform", "ubuntu"]
    bios      = "ovmf"

    clone {
        vm_id = 1000
        full  = true
    }

    agent {
        enabled = true
    }

    memory {
        dedicated = 1024
    }

    efi_disk {
      datastore_id = "local"
      file_format  = "qcow2"
      type         = "4m"
      pre_enrolled_keys = true
    }

    initialization {
        datastore_id = "vm-data"
        file_format  = "qcow2"

        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    operating_system {
        type = "l26"
    }

    serial_device {}

}

output "vm_ipv4_address" {
    value = proxmox_virtual_environment_vm.test_vm.ipv4_addresses
}