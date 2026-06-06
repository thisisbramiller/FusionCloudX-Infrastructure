# Thin single-VM module: one full-cloned Ubuntu QEMU guest on node "pve".
# Extracted from the flat terraform/qemu-vm.tf for_each resource (one instance).
# The consuming root wires the cloud-init snippet IDs, the template VMID, and any
# ordering against the template resource.
#
# prevent_destroy SEATBELT: prevent_destroy must be a static literal on the
# resource (HCL forbids a variable), and module call sites cannot pass a
# lifecycle block. This module is shared by PROTECTED singletons (gitlab,
# opconnect) AND DISPOSABLE apps (mealie/tandoor/immich/runitup), so we split
# the single VM into two count-gated resource blocks with BYTE-IDENTICAL bodies
# that differ ONLY in the lifecycle block:
#   - "protected"  (count = var.protected ? 1 : 0) carries prevent_destroy = true
#   - "disposable" (count = var.protected ? 0 : 1) is destroyable
# var.protected (default false) selects exactly one. outputs.tf coalesces across
# the pair with one(concat(...)). Keep the two bodies in lockstep on any edit —
# the shared scalars are factored into local.vm_* below to cut drift risk.

locals {
  vm_node_name      = "pve"
  vm_bios           = "seabios"
  vm_cpu_type       = "x86-64-v2-AES"
  vm_clone_retries  = 10
  vm_os_type        = "l26"
  vm_extra_disk_set = var.extra_disk_size_gb != null ? [1] : []
}

# PROTECTED variant — prevent_destroy = true. Built when var.protected = true.
resource "proxmox_virtual_environment_vm" "protected" {
  count = var.protected ? 1 : 0

  vm_id     = var.vm_id
  name      = var.name
  node_name = local.vm_node_name
  started   = var.started
  on_boot   = var.on_boot
  tags      = var.tags
  bios      = local.vm_bios

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = local.vm_clone_retries
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = var.memory_mb
  }

  cpu {
    cores = var.cores
    type  = local.vm_cpu_type
  }

  # Optional extra OS disk (scsi1) on the target datastore. scsi0 is reserved for
  # cloud-init; scsi1 is the cloned OS disk from the template.
  dynamic "disk" {
    for_each = local.vm_extra_disk_set
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
    type = local.vm_os_type
  }

  serial_device {}

  lifecycle {
    prevent_destroy = true # protected singleton seatbelt (literal)
    ignore_changes = [
      initialization, # Ignore cloud-init state changes
    ]
  }
}

# DISPOSABLE variant — destroyable. Built when var.protected = false (default).
# Body byte-identical to "protected" above except the lifecycle block.
resource "proxmox_virtual_environment_vm" "disposable" {
  count = var.protected ? 0 : 1

  vm_id     = var.vm_id
  name      = var.name
  node_name = local.vm_node_name
  started   = var.started
  on_boot   = var.on_boot
  tags      = var.tags
  bios      = local.vm_bios

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = local.vm_clone_retries
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = var.memory_mb
  }

  cpu {
    cores = var.cores
    type  = local.vm_cpu_type
  }

  # Optional extra OS disk (scsi1) on the target datastore. scsi0 is reserved for
  # cloud-init; scsi1 is the cloned OS disk from the template.
  dynamic "disk" {
    for_each = local.vm_extra_disk_set
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
    type = local.vm_os_type
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      initialization, # Ignore cloud-init state changes
    ]
  }
}
