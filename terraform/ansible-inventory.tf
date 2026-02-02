# ==============================================================================
# Ansible Inventory via Terraform Ansible Provider
# ==============================================================================
# Defines Ansible inventory as Terraform resources
# Inventory is read by cloud.terraform.terraform_provider plugin
# ==============================================================================

# ------------------------------------------------------------------------------
# Groups
# ------------------------------------------------------------------------------

resource "ansible_group" "postgresql" {
  name = "postgresql"
  variables = {
    ansible_user                = "root"
    ansible_python_interpreter  = "/usr/bin/python3"
    ansible_ssh_common_args     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "application_servers" {
  name = "application_servers"
  variables = {
    ansible_user                = "ansible"
    ansible_python_interpreter  = "/usr/bin/python3"
    ansible_ssh_common_args     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "monitoring" {
  name = "monitoring"
  variables = {
    ansible_user                = "ansible"
    ansible_python_interpreter  = "/usr/bin/python3"
    ansible_ssh_common_args     = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "homelab" {
  name     = "homelab"
  children = [
    ansible_group.postgresql.name,
    ansible_group.application_servers.name,
    ansible_group.monitoring.name
  ]
  variables = {
    ansible_connection = "ssh"
  }
}

# ------------------------------------------------------------------------------
# Hosts - LXC Containers
# ------------------------------------------------------------------------------

resource "ansible_host" "postgresql" {
  name   = proxmox_virtual_environment_container.postgresql.initialization[0].hostname
  groups = [ansible_group.postgresql.name]

  variables = {
    ansible_host = try(
      proxmox_virtual_environment_container.postgresql.ipv4["eth0"],
      "IP not available"
    )
    vm_id = proxmox_virtual_environment_container.postgresql.vm_id
    type  = "lxc"
  }
}

# ------------------------------------------------------------------------------
# Hosts - QEMU VMs
# ------------------------------------------------------------------------------

resource "ansible_host" "vms" {
  for_each = proxmox_virtual_environment_vm.qemu-vm

  name   = each.key
  groups = [ansible_group.application_servers.name]

  variables = {
    ansible_host = try(
      each.value.ipv4_addresses[1][0],
      "IP not available"
    )
    vm_id = each.value.id
    type  = "qemu"
  }
}
