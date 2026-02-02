# ==============================================================================
# Terraform Outputs - FusionCloudX Infrastructure
# ==============================================================================
# Clean, consolidated outputs for operational visibility
# Ansible inventory is managed via Terraform Ansible Provider (see ansible-inventory.tf)
# ==============================================================================

# ------------------------------------------------------------------------------
# Infrastructure Summary
# ------------------------------------------------------------------------------

output "infrastructure_summary" {
  description = "Complete infrastructure deployment summary"
  value = {
    # VMs with IPs from QEMU guest agent
    vms = {
      for key, vm in proxmox_virtual_environment_vm.qemu-vm :
      key => {
        id       = vm.id
        name     = vm.name
        ip       = try(vm.ipv4_addresses[1][0], "IP not available")
        cpu      = vm.cpu[0].cores
        memory   = vm.memory[0].dedicated
        status   = vm.started ? "running" : "stopped"
      }
    }

    # LXC containers with IPs from network config
    containers = {
      postgresql = {
        id       = proxmox_virtual_environment_container.postgresql.vm_id
        hostname = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
        ip       = try(proxmox_virtual_environment_container.postgresql.ipv4["eth0"], "IP not available")
        cpu      = var.postgresql_lxc_config.cpu_cores
        memory   = var.postgresql_lxc_config.memory_mb
        disk     = var.postgresql_lxc_config.disk_gb
        status   = proxmox_virtual_environment_container.postgresql.started ? "running" : "stopped"
      }
    }

    # Database configurations
    databases = {
      for db in var.postgresql_databases :
      db.name => {
        description = db.description
        owner       = db.owner
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Quick Access - Individual Resources
# ------------------------------------------------------------------------------

output "gitlab_url" {
  description = "GitLab web interface URL"
  value       = "http://${try(proxmox_virtual_environment_vm.qemu-vm["gitlab"].ipv4_addresses[1][0], "IP-not-available")}"
}

output "postgresql_connection" {
  description = "PostgreSQL connection details"
  value = {
    host     = try(proxmox_virtual_environment_container.postgresql.ipv4["eth0"], "IP not available")
    port     = 5432
    hostname = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
    databases = [for db in var.postgresql_databases : db.name]
  }
}

# ------------------------------------------------------------------------------
# 1Password Credential References
# ------------------------------------------------------------------------------

output "onepassword_items" {
  description = "1Password item IDs for credential retrieval"
  value = {
    gitlab = {
      root_password = onepassword_item.gitlab_root_password.id
      runner_token  = onepassword_item.gitlab_runner_token.id
    }
    postgresql = {
      admin_password = onepassword_item.postgresql_admin.id
      wazuh_password = onepassword_item.wazuh_db_user.id
    }
    ssh = {
      ansible_key = onepassword_item.ansible_ssh_key.id
    }
  }
}

# ------------------------------------------------------------------------------
# SSH Key Information
# ------------------------------------------------------------------------------

output "ansible_ssh_public_key" {
  description = "Public SSH key for Ansible access (for reference/debugging)"
  value       = trimspace(tls_private_key.ansible.public_key_openssh)
}

output "ansible_ssh_key_fingerprint" {
  description = "SHA256 fingerprint of the Ansible SSH key"
  value       = tls_private_key.ansible.public_key_fingerprint_sha256
}
