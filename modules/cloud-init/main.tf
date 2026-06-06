# Parameterized cloud-init module: creates the user-data + vendor-data snippet
# files for one guest. Replaces the flat terraform/cloud-init.tf (standard) and
# terraform/cloud-init-gitlab.tf (gitlab variant) with one configurable module.
#
# - user-data: ansible user + key + growpart + SSH hardening (verbatim from the
#   flat cloud-init.tf; only the hostname + key are parameterized).
# - vendor-data: timezone + package_update + (packages + extra_packages) + runcmd,
#   plus optional fqdn / package_upgrade / debconf_selections (gitlab variant).

locals {
  # Assemble the vendor-data cloud-config from the base set plus optional fields.
  # Built with yamlencode so merged lists + optional keys render cleanly; the
  # #cloud-config shebang is prepended (it must be the first line).
  vendor_data_config = merge(
    {
      timezone       = "America/Chicago"
      package_update = true
      packages       = concat(var.packages, var.extra_packages)
      runcmd         = var.runcmd
    },
    var.fqdn != null ? { hostname = var.name, fqdn = var.fqdn } : {},
    var.package_upgrade ? { package_upgrade = true } : {},
    var.debconf_selections != null ? { debconf_selections = var.debconf_selections } : {},
  )
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.datastore_id
  node_name    = "pve"

  source_raw {
    data = <<-EOF
        #cloud-config
        hostname: ${var.name}
        users:
          - name: ansible
            gecos: Ansible User
            shell: /bin/bash
            groups: [sudo, users]
            sudo: "ALL=(ALL) NOPASSWD:ALL"
            ssh_authorized_keys:
              - ${trimspace(var.ansible_pubkey)}
            lock_passwd: true
        ssh_pwauth: false
        disable_root: true
        growpart:
          mode: auto
          devices: ['/']
        write_files:
          - path: /var/lib/cloud-init.provision.ready
            content: "Cloud-init provisioning complete.\n"
            permissions: '0644'
        EOF

    file_name = "user-data-cloud-config-${var.name}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "vendor_data" {
  content_type = "snippets"
  datastore_id = var.datastore_id
  node_name    = "pve"

  source_raw {
    data = "#cloud-config\n${yamlencode(local.vendor_data_config)}"

    file_name = "vendor-data-cloud-config-${var.name}.yaml"
  }
}
