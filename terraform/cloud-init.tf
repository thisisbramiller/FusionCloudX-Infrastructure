resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  for_each = var.vm_configs
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "zero"

  source_raw {
    data = <<-EOF
        #cloud-config
        hostname: ${each.value.name}
        timezone: America/Chicago
        users:
          - default
          - name: fcx
            groups:
              - sudo
            shell: /bin/bash
            # NOTE: Passwordless sudo for lab/dev environments. Restrict for production use.
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_import_id: 
              - gh:thisisbramiller
            lock_passwd: true
        package_update: true
        packages:
          - qemu-guest-agent
          - net-tools
          - curl
        runcmd:
          - systemctl enable qemu-guest-agent
          - systemctl start qemu-guest-agent
          - echo "done" > /tmp/cloud-config.done
        EOF

    file_name = "user-data-cloud-config-${each.value.name}.yaml"
  }
}