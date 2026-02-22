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
      disk,           # Disk may be moved to different datastore post-clone
    ]
  }

}

# ==============================================================================
# Post-Clone Disk Migration
# ==============================================================================
# The Proxmox provider doesn't support cloning VM disks to a different
# datastore. For VMs that need local SSD storage (e.g. Immich for database
# performance), we move the disk after clone via qm move-disk.
# ==============================================================================

resource "null_resource" "vm_disk_migration" {
  for_each = {
    for key, config in var.vm_configs : key => config
    if config.datastore_id != "vm-data"
  }

  depends_on = [proxmox_virtual_environment_vm.qemu-vm]

  triggers = {
    vm_id        = var.vm_configs[each.key].vm_id
    datastore_id = each.value.datastore_id
  }

  # Stop VM before disk move (provider may have started it)
  provisioner "remote-exec" {
    inline = [
      "qm stop ${each.value.vm_id} --timeout 60 || true",
      "sleep 5",
      "qm move-disk ${each.value.vm_id} scsi1 ${each.value.datastore_id} --delete 1",
      "qm start ${each.value.vm_id}",
    ]

    connection {
      type = "ssh"
      host = var.proxmox_ssh_host
      user = "root"
    }
  }
}
