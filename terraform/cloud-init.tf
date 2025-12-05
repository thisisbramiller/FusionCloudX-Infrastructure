resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  for_each     = var.vm_configs
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "zero"

  source_raw {
    data = <<-EOF
        #cloud-config
        hostname: ${each.value.name}
        users:
          - default
          - name: fcx
            groups:
              - sudo
            shell: /bin/bash
            # NOTE: Passwordless sudo - appropriate for homelab/development infrastructure.
            # These VMs are for testing and development, not production workloads.
            # Production infrastructure will be deployed separately on AWS.
            sudo: ALL=(ALL) NOPASSWD:ALL
            ssh_import_id: 
              - gh:thisisbramiller
            lock_passwd: true
        EOF

    file_name = "user-data-cloud-config-${each.value.name}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "vendor_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "zero"

  source_raw {
    data = <<-EOF
        #cloud-config
        timezone: America/Chicago
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

    file_name = "vendor-data-cloud-config.yaml"
  }
}