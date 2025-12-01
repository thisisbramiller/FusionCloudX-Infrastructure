resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
    content_type = "snippets"
    datastore_id = "nas-infrastructure"
    node_name    = "zero"

    source_raw {
        data = <<-EOF
        #cloud-config
        hostname: test-ubuntu
        timezone: America/Chicago
        users:
          - default
          - name: ubuntu
            groups:
              - sudo
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
        package_update: true
        packages:
          - qemu-guest-agent
          - net-tools
          - curl
        runcmd:
          - systemctl enable qemu guest-agent
          - systemctl start qemu guest-agent
          - echo "done" > /tmp/cloud-config.done
        EOF

        file_name = "user-data-cloud-config.yaml"
    }
}