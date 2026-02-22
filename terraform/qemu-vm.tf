resource "proxmox_virtual_environment_vm" "qemu-vm" {
  for_each = var.vm_configs

  vm_id     = each.value.vm_id
  name      = each.value.name
  node_name = "pve"
  started   = each.value.started
  on_boot   = try(each.value.on_boot, true)
  tags      = ["terraform", "ubuntu"]
  bios      = "seabios"

  depends_on = [proxmox_virtual_environment_vm.ubuntu-template]

  clone {
    vm_id   = 1000
    full    = each.value.full_clone
    retries = 10
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

  # For VMs with non-default datastore, place the OS disk (scsi1) on target storage.
  # scsi0 is reserved for cloud-init; scsi1 is the cloned OS disk from the template.
  dynamic "disk" {
    for_each = each.value.datastore_id != "vm-data" ? [1] : []
    content {
      datastore_id = each.value.datastore_id
      interface    = "scsi1"
      size         = 32
      file_format  = "raw"
    }
  }

  initialization {
    datastore_id = "vm-data"
    file_format  = "qcow2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config[each.key].id
    # Use gitlab-specific vendor_data for gitlab, standard for others
    vendor_data_file_id = each.key == "gitlab" ? proxmox_virtual_environment_file.gitlab_vendor_data_cloud_config.id : proxmox_virtual_environment_file.vendor_data_cloud_config.id
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      initialization, # Ignore cloud-init state changes
    ]
  }

}
