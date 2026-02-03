# ==============================================================================
# GitLab VM: Enhanced Vendor Data
# ==============================================================================
# This vendor_data is specifically for the gitlab VM to install
# additional packages needed for GitLab prerequisites
# ==============================================================================

resource "proxmox_virtual_environment_file" "gitlab_vendor_data_cloud_config" {
  content_type = "snippets"
  datastore_id = "nas-infrastructure"
  node_name    = "pve"

  source_raw {
    data = <<-EOF
        #cloud-config
        hostname: gitlab
        fqdn: gitlab.fusioncloudx.home
        timezone: America/Chicago
        package_update: true
        package_upgrade: true
        packages:
          - qemu-guest-agent
          # GitLab prerequisites
          - curl
          - ca-certificates
          - perl
          - openssh-server
          - postfix
          - tzdata
          - ufw
          # Python for Ansible management
          - python3
          - python3-pip

        # Configure postfix for local mail delivery (non-interactive)
        debconf_selections: |
          postfix postfix/main_mailer_type select 'Internet Site'
          postfix postfix/mailname string gitlab.fusioncloudx.home

        runcmd:
          - systemctl enable qemu-guest-agent
          - systemctl start qemu-guest-agent
          # Enable SSH
          - systemctl enable ssh
          - systemctl start ssh
          # Configure postfix
          - DEBIAN_FRONTEND=noninteractive dpkg-reconfigure postfix
          # Smoke tests - verify installations
          - |
            echo "=== GitLab Cloud-Init Verification ===" > /var/log/cloud-init-verify.log
            echo "Timestamp: $(date)" >> /var/log/cloud-init-verify.log
            echo "" >> /var/log/cloud-init-verify.log
            curl --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: curl not installed" >> /var/log/cloud-init-verify.log
            python3 --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: python3 not installed" >> /var/log/cloud-init-verify.log
            postconf mail_version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: postfix not installed" >> /var/log/cloud-init-verify.log
            ufw --version >> /var/log/cloud-init-verify.log 2>&1 || echo "FAIL: ufw not installed" >> /var/log/cloud-init-verify.log
            echo "" >> /var/log/cloud-init-verify.log
            echo "=== Verification Complete ===" >> /var/log/cloud-init-verify.log
          - echo "done" > /tmp/cloud-config.done
          # Create marker file for GitLab cloud-init completion
          - echo "GitLab VM cloud-init completed" > /var/lib/cloud-init.gitlab.ready
        EOF

    file_name = "vendor-data-cloud-config-gitlab.yaml"
  }
}
