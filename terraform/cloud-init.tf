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
          - name: ansible
            gecos: Ansible User
            shell: /bin/bash
            groups: [sudo, users]
            sudo: "ALL=(ALL) NOPASSWD:ALL"
            ssh_import_id: 
              - gh:thisisbramiller
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