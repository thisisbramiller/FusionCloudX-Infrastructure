output "vm_ipv4_addresses" {
  value = {
    for key, vm in proxmox_virtual_environment_vm.qemu-vm :
    key => try(vm.ipv4_addresses[1][0], "IP not available")
  }
  description = "VM IPv4 addresses from QEMU guest agent (map of VM name to IP)"
}

# GitLab-specific output for easy reference
output "gitlab_ipv4_address" {
  description = "IPv4 address of GitLab VM"
  value = try(
    proxmox_virtual_environment_vm.qemu-vm["gitlab"].ipv4_addresses[1][0],
    "DHCP address not yet assigned"
  )
}

# ==============================================================================
# PostgreSQL LXC Container Outputs
# ==============================================================================
# Single PostgreSQL instance outputs
# ==============================================================================

output "postgresql_container_id" {
  value       = proxmox_virtual_environment_container.postgresql.vm_id
  description = "PostgreSQL LXC container ID"
}

output "postgresql_container_hostname" {
  value       = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
  description = "PostgreSQL LXC container hostname"
}

output "postgresql_container_ipv4" {
  value       = try(proxmox_virtual_environment_container.postgresql.initialization[0].ip_config[0].ipv4[0].address, "IP not available - check DHCP")
  description = "PostgreSQL LXC container IPv4 address from DHCP"
}

# Combined output for Ansible inventory generation
output "ansible_inventory_postgresql" {
  value = {
    hostname  = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
    ip        = try(proxmox_virtual_environment_container.postgresql.initialization[0].ip_config[0].ipv4[0].address, "IP not available")
    vm_id     = proxmox_virtual_environment_container.postgresql.vm_id
    databases = var.postgresql_databases
  }
  description = "PostgreSQL container details formatted for Ansible inventory (includes database list)"
}

# ==============================================================================
# 1Password Outputs
# ==============================================================================
# Reference IDs for the database credential items in 1Password
# ==============================================================================

output "onepassword_postgresql_admin_id" {
  value       = onepassword_item.postgresql_admin.id
  description = "1Password item ID for PostgreSQL admin (postgres) credentials"
}

output "onepassword_semaphore_db_id" {
  value       = onepassword_item.semaphore_db_user.id
  description = "1Password item ID for Semaphore database user credentials"
}

output "onepassword_wazuh_db_id" {
  value       = onepassword_item.wazuh_db_user.id
  description = "1Password item ID for Wazuh database user credentials"
}

# Summary output
output "postgresql_deployment_summary" {
  value = {
    container = {
      id       = proxmox_virtual_environment_container.postgresql.vm_id
      hostname = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
      ip       = try(proxmox_virtual_environment_container.postgresql.initialization[0].ip_config[0].ipv4[0].address, "IP not available")
      memory   = var.postgresql_lxc_config.memory_mb
      cpu      = var.postgresql_lxc_config.cpu_cores
      disk     = var.postgresql_lxc_config.disk_gb
    }
    databases = var.postgresql_databases
    secrets = {
      admin_password_1password_id     = onepassword_item.postgresql_admin.id
      semaphore_password_1password_id = onepassword_item.semaphore_db_user.id
      wazuh_password_1password_id     = onepassword_item.wazuh_db_user.id
    }
  }
  description = "Complete PostgreSQL deployment summary"
}
