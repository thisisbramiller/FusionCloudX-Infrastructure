# Thin single-LXC module: one unprivileged Debian container on node "pve".
# Extracted from the flat terraform/lxc-postgresql.tf. Ansible owns service
# identity (PostgreSQL install/config); this module only builds the substrate.
resource "proxmox_virtual_environment_container" "this" {
  node_name = "pve"
  vm_id     = var.vm_id

  started       = var.started
  start_on_boot = var.on_boot
  unprivileged  = true # Security best practice — always use unprivileged containers

  # Operating System — Debian template from Proxmox. Ansible prerequisites
  # (python3, sudo) installed via the bootstrap playbook using the raw module.
  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  # Network — DHCP on vmbr0. IP retrieved via output after creation.
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  console {
    enabled   = true
    type      = "console"
    tty_count = 2
  }

  # Initialization — SSH key injected for Ansible access.
  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [
        trimspace(var.ssh_pubkey)
      ]
    }
  }

  features {
    nesting = var.nesting
  }

  # Free-text Proxmox "Notes" field (carried from the flat terraform/lxc-postgresql.tf).
  # Null when empty so the bpg provider does not perpetually diff (provider #611/#762)
  # for any future consumer that omits a description.
  description = var.description != "" ? var.description : null

  tags = var.tags

  # This module is only ever consumed by the protected postgresql singleton, so
  # prevent_destroy is an UNCONDITIONAL literal here (literal-only by HCL rule).
  lifecycle {
    prevent_destroy = true
  }
}
