# ==============================================================================
# Ansible-Ready LXC Template Automation
# ==============================================================================
# Creates custom Debian 12 LXC template with Ansible prerequisites if it doesn't exist
# Template includes: sudo, python3, python3-pip, ssh-import-id
#
# This resource is idempotent - safe to run multiple times
# ==============================================================================

resource "null_resource" "ansible_ready_lxc_template" {
  # Re-run if template creation script changes
  triggers = {
    script_hash = filemd5("${path.module}/../scripts/ensure-ansible-ready-template.sh")
  }

  # Run wrapper script that checks for template and creates if missing
  provisioner "local-exec" {
    command = <<-EOT
      echo "Ensuring Ansible-ready LXC template exists..."

      # Upload and execute the wrapper script on Proxmox host
      cat "${path.module}/../scripts/ensure-ansible-ready-template.sh" | \
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        terraform@${var.proxmox_ssh_host} 'bash -s'
    EOT

    interpreter = ["bash", "-c"]
  }
}

# ==============================================================================
# Dependency Configuration
# ==============================================================================
# The PostgreSQL container MUST wait for the template to be available
# This is handled by depends_on in lxc-postgresql.tf
# ==============================================================================
