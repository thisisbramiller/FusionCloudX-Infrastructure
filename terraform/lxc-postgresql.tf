# ==============================================================================
# PostgreSQL LXC Container Infrastructure
# ==============================================================================
# This file defines a SINGLE LXC container for PostgreSQL database server
# This container will host MULTIPLE databases (wazuh, etc.)
# Configuration and PostgreSQL installation is handled by Ansible
#
# PREREQUISITE - One-Time Setup:
# Create custom LXC template with Ansible prerequisites pre-installed:
#   cat scripts/create-ansible-ready-lxc-template.sh | ssh root@192.168.40.206 'bash -s'
#
# This is a ONE-TIME operation. Once template exists, all future deployments are automated.
# Template includes: sudo, python3, python3-pip, ssh-import-id
#
# Why custom template?
# - LXC containers don't support cloud-init
# - Hook scripts require root@pam (not API tokens)
# - Provisioners require interactive SSH approval
# - Custom template = clean, repeatable, zero runtime provisioning
# ==============================================================================

# Create single PostgreSQL LXC container
# This container will host multiple databases for different services
resource "proxmox_virtual_environment_container" "postgresql" {
  # Ensure Ansible-ready template exists before creating container
  depends_on = [null_resource.ansible_ready_lxc_template]

  node_name = "pve"
  vm_id     = var.postgresql_lxc_config.vm_id

  # Container basic settings
  description   = var.postgresql_lxc_config.description
  started       = var.postgresql_lxc_config.started
  start_on_boot = var.postgresql_lxc_config.on_boot
  unprivileged  = true # Security best practice - always use unprivileged containers

  # Operating System - custom Ansible-ready template
  # Template must be created first (one-time): scripts/create-ansible-ready-lxc-template.sh
  operating_system {
    template_file_id = "nas-infrastructure:vztmpl/debian-12-ansible-ready.tar.zst"
    type             = "debian"
  }

  # CPU Configuration
  cpu {
    cores = var.postgresql_lxc_config.cpu_cores
  }

  # Memory Configuration
  memory {
    dedicated = var.postgresql_lxc_config.memory_mb
    swap      = 512 # Small swap for safety
  }

  # Root Disk Configuration
  disk {
    datastore_id = "vm-data"
    size         = var.postgresql_lxc_config.disk_gb
  }

  # Network Configuration - DHCP on vmbr0
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
    # DHCP - IP will be retrieved via output after creation
  }

  # Console Settings
  console {
    enabled   = true
    type      = "console"
    tty_count = 2
  }

  # Initialization - SSH keys from GitHub (hardcoded for initial access)
  initialization {
    hostname = var.postgresql_lxc_config.hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [
        # SSH keys from GitHub - thisisbramiller
        # These match what ssh-import-id would fetch
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfloPNsap5v++MwS6YA9eqiRr9IiyxhBpMVVRT26x4c",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2KVCN+voRL8xt7MQzVayUzNq5ETiS7uNHdHo1iHERE"
      ]
    }
  }

  # Features
  features {
    nesting = true # Allow Docker/nested containers if needed
  }

  # Tags for organization
  tags = var.postgresql_lxc_config.tags
}

# ==============================================================================
# 1Password Integration - PostgreSQL Database Credentials
# ==============================================================================
# These resources create 1Password items for database credentials
# Ansible will retrieve these secrets during configuration
# ==============================================================================

# PostgreSQL Admin (postgres) password item in 1Password
resource "onepassword_item" "postgresql_admin" {
  vault    = var.onepassword_vault_id
  category = "database"
  title    = "PostgreSQL Admin (postgres)"
  tags     = ["terraform", "postgresql", "homelab", "admin"]

  type     = "postgresql"
  hostname = "${var.postgresql_lxc_config.hostname}.fusioncloudx.home"
  port     = "5432"
  database = "postgres"
  username = "postgres"

  password_recipe {
    length  = 32
    symbols = true
  }
}

# Wazuh database user password item in 1Password
resource "onepassword_item" "wazuh_db_user" {
  vault    = var.onepassword_vault_id
  category = "database"
  title    = "PostgreSQL - Wazuh Database User"
  tags     = ["terraform", "postgresql", "wazuh", "homelab"]

  type     = "postgresql"
  hostname = "${var.postgresql_lxc_config.hostname}.fusioncloudx.home"
  port     = "5432"
  database = "wazuh"
  username = "wazuh"

  password_recipe {
    length  = 32
    symbols = true
  }
}
