# Thin single-VM module: one full-cloned Ubuntu QEMU guest on node "pve".
# Extracted from the flat terraform/qemu-vm.tf for_each resource (one instance).
# The consuming root wires the cloud-init snippet IDs, the template VMID, and any
# ordering against the template resource.
resource "proxmox_virtual_environment_vm" "this" {
  vm_id     = var.vm_id
  name      = var.name
  node_name = "pve"
  started   = var.started
  on_boot   = var.on_boot
  tags      = var.tags
  bios      = "seabios"

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 10
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = var.memory_mb
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  # Optional extra OS disk (scsi1) on the target datastore. scsi0 is reserved for
  # cloud-init; scsi1 is the cloned OS disk from the template.
  dynamic "disk" {
    for_each = var.extra_disk_size_gb != null ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = var.extra_disk_size_gb
      file_format  = "raw"
    }
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id   = var.user_data_file_id
    vendor_data_file_id = var.vendor_data_file_id
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
