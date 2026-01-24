resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  for_each     = var.vm_configs
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "pve"

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
  node_name    = "pve"

  source_raw {
    data = <<-EOF
        #cloud-config
        timezone: America/Chicago
        package_update: true
        packages:
          - qemu-guest-agent
          - net-tools
          - curl
          # Python for Ansible management (ALL VMs need this)
          - python3
          - python3-pip
        runcmd:
          - systemctl enable qemu-guest-agent
          - systemctl start qemu-guest-agent
          - echo "done" > /tmp/cloud-config.done
        EOF

    file_name = "vendor-data-cloud-config.yaml"
  }
}

# ==============================================================================
# Semaphore-UI Control Plane: Enhanced Vendor Data
# ==============================================================================
# This vendor_data is specifically for the semaphore-ui VM to install
# additional packages needed for the Infrastructure Control Plane
# ==============================================================================

resource "proxmox_virtual_environment_file" "semaphore_vendor_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "pve"

  source_raw {
    data = <<-EOF
        #cloud-config
        timezone: America/Chicago
        package_update: true
        package_upgrade: true
        packages:
          - qemu-guest-agent
          # Control plane specific packages (base packages inherited from standard vendor_data)
          - wget
          - git
          - unzip
          - gnupg
          - software-properties-common
          - apt-transport-https
          - ca-certificates
          # Ansible (via apt, not pip - stable and maintained by Ubuntu)
          - ansible
          - ansible-core
          # Build tools (for some Ansible modules)
          - build-essential
          - libssl-dev
          - libffi-dev
          - python3-dev

        write_files:
          # Create directory structure for infrastructure repo
          - path: /opt/infrastructure/.gitkeep
            content: "Infrastructure repository will be cloned here\n"
            permissions: '0644'

        runcmd:
          - systemctl enable qemu-guest-agent
          - systemctl start qemu-guest-agent
          # Create ansible user home directories
          - mkdir -p /home/ansible/.ssh
          - mkdir -p /home/ansible/.ansible
          - chown -R ansible:ansible /home/ansible

          # Set proper ownership for infrastructure directory
          - chown -R ansible:ansible /opt/infrastructure

          # Smoke tests - verify installations
          - |
            echo "=== Semaphore-UI Cloud-Init Verification ===" > /var/log/cloud-init-verify.log
            echo "Timestamp: $(date)" >> /var/log/cloud-init-verify.log
            echo "" >> /var/log/cloud-init-verify.log
            ansible --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: ansible not installed" >> /var/log/cloud-init-verify.log
            python3 --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: python3 not installed" >> /var/log/cloud-init-verify.log
            git --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: git not installed" >> /var/log/cloud-init-verify.log
            echo "" >> /var/log/cloud-init-verify.log
            echo "=== Verification Complete ===" >> /var/log/cloud-init-verify.log

          # Create marker file
          - echo "Semaphore-UI cloud-init complete - $(date)" > /var/lib/cloud-init.semaphore.ready
          - echo "done" > /tmp/cloud-config.done
        EOF

    file_name = "vendor-data-cloud-config-semaphore.yaml"
  }
}