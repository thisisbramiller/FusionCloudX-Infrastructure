# ==============================================================================
# PostgreSQL LXC Container Infrastructure
# ==============================================================================
# This file defines a SINGLE LXC container for PostgreSQL database server
# This container will host MULTIPLE databases (semaphore, wazuh, etc.)
# Configuration and PostgreSQL installation is handled by Ansible
# ==============================================================================

# Download Debian 12 LXC template
resource "proxmox_virtual_environment_download_file" "debian12_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "nas-infrastructure"
  node_name    = "zero"

  # Debian 12 Standard template from official Proxmox repository
  # You can find available templates at: http://download.proxmox.com/images/system/
  url = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"

  # Alternative: Download from your Proxmox web UI (recommended)
  # Navigate to: Datacenter > zero > nas-infrastructure > CT Templates > Download
  # Select: debian-12-standard (latest version)

  # Only download once - don't re-download on subsequent runs
  lifecycle {
    ignore_changes = [url]
  }
}

# Create single PostgreSQL LXC container
# This container will host multiple databases for different services
resource "proxmox_virtual_environment_container" "postgresql" {
  node_name = "zero"
  vm_id     = var.postgresql_lxc_config.vm_id

  # Container basic settings
  description   = var.postgresql_lxc_config.description
  started       = var.postgresql_lxc_config.started
  start_on_boot = var.postgresql_lxc_config.on_boot
  unprivileged  = true # Security best practice - always use unprivileged containers

  # Operating System
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian12_lxc_template.id
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

  # Initialization - SSH keys for root access
  initialization {
    hostname = var.postgresql_lxc_config.hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [
        # SSH public key for ansible/terraform user - replace with your key
        trimspace(file("~/.ssh/id_rsa.pub"))
      ]
    }
  }

  # Features
  features {
    nesting = true # Allow Docker/nested containers if needed
  }

  # Tags for organization
  tags = var.postgresql_lxc_config.tags

  # Depends on template being downloaded
  depends_on = [
    proxmox_virtual_environment_download_file.debian12_lxc_template
  ]
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

# Semaphore database user password item in 1Password
resource "onepassword_item" "semaphore_db_user" {
  vault    = var.onepassword_vault_id
  category = "database"
  title    = "PostgreSQL - Semaphore Database User"
  tags     = ["terraform", "postgresql", "semaphore", "homelab"]

  type     = "postgresql"
  hostname = "${var.postgresql_lxc_config.hostname}.fusioncloudx.home"
  port     = "5432"
  database = "semaphore"
  username = "semaphore"

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
