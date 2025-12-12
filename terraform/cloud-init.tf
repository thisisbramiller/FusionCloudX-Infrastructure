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

# ==============================================================================
# Semaphore-UI Control Plane: Enhanced Vendor Data
# ==============================================================================
# This vendor_data is specifically for the semaphore-ui VM to install
# additional packages needed for the Infrastructure Control Plane
# ==============================================================================

resource "proxmox_virtual_environment_file" "semaphore_vendor_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "zero"

  source_raw {
    data = <<-EOF
        #cloud-config
        timezone: America/Chicago
        package_update: true
        package_upgrade: true
        packages:
          # Base system packages
          - qemu-guest-agent
          - net-tools
          - curl
          - wget
          - git
          - unzip
          - gnupg
          - software-properties-common
          - apt-transport-https
          - ca-certificates
          # Python for Ansible
          - python3
          - python3-pip
          - python3-venv
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

          # Placeholder for environment variables (will be configured by Ansible)
          - path: /etc/environment.d/semaphore.conf
            content: |
              # 1Password and Proxmox environment variables
              # These will be configured by the bootstrap Ansible playbook
              # OP_SERVICE_ACCOUNT_TOKEN=<to-be-configured>
              # PROXMOX_VE_ENDPOINT=https://zero.fusioncloudx.home:8006
            permissions: '0644'

          # SSH config for ansible user (will be updated by bootstrap)
          - path: /home/ansible/.ssh/config
            content: |
              # SSH Configuration for Infrastructure Management
              Host github.com
                HostName github.com
                User git
                IdentityFile ~/.ssh/github_deploy_key
                StrictHostKeyChecking accept-new

              Host proxmox zero.fusioncloudx.home
                HostName zero.fusioncloudx.home
                User terraform
                IdentityFile ~/.ssh/proxmox_terraform_key
                StrictHostKeyChecking accept-new

              Host 192.168.*
                User ansible
                IdentityFile ~/.ssh/id_ed25519
                StrictHostKeyChecking accept-new
            owner: ansible:ansible
            permissions: '0600'

        runcmd:
          # Enable and start qemu-guest-agent
          - systemctl enable qemu-guest-agent
          - systemctl start qemu-guest-agent

          # Create ansible user home directories
          - mkdir -p /home/ansible/.ssh
          - mkdir -p /home/ansible/.ansible
          - chown -R ansible:ansible /home/ansible

          # Set proper ownership for infrastructure directory
          - chown -R ansible:ansible /opt/infrastructure

          # Install Ansible via pip (latest stable version)
          - python3 -m pip install --upgrade pip
          - python3 -m pip install ansible ansible-core

          # Create marker file
          - echo "Semaphore-UI cloud-init complete - $(date)" > /var/lib/cloud-init.semaphore.ready
        EOF

    file_name = "vendor-data-cloud-config-semaphore.yaml"
  }
}