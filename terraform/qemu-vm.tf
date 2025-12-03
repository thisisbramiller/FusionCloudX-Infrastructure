variable vm_configs {
  type = map(object({
    vm_id = number
    name = string
    memory_mb = number
    cpu_cores = number
    started = bool
  }))

  default = {
    "teleport" = {
      vm_id     = 1101
      name      = "teleport"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
    "ansible" = {
      vm_id     = 1102
      name      = "ansible"
      memory_mb = 2048
      cpu_cores = 2
      started   = true
    }
    "wazuh" = {
      vm_id     = 1103
      name      = "wazuh"
      memory_mb = 4096
      cpu_cores = 2
      started   = true
    }
  }
}

resource "proxmox_virtual_environment_vm" "qemu-vm" {
  for_each = var.vm_configs

  vm_id = each.value.vm_id
  name      = each.value.name
  node_name = "zero"
  started   = each.value.started
  on_boot   = false
  tags      = ["terraform", "ubuntu"]
  bios      = "seabios"



  depends_on = [proxmox_virtual_environment_vm.ubuntu-template]

  clone {
    vm_id = 1000
    full  = false
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = each.value.memory_mb
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "x86-64-v2-AES"
  }

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

