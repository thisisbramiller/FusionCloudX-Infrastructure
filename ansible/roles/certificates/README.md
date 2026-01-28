# Ansible Role: certificates

Deploys FusionCloudX CA and server certificates to VMs and services.

## Description

This role installs Root CA and Intermediate CA certificates to the system trust store, and deploys server certificates to services (nginx, apache, etc.). It integrates with 1Password for certificate retrieval.

## Requirements

- Ansible 2.9+
- 1Password CLI (`op`) configured on control node
- Target hosts: Ubuntu/Debian-based Linux

## Role Variables

### Required Variables

```yaml
certificates_root_ca: "{{ lookup('op_document', 'root-ca.pem', vault='FusionCloudX') }}"
certificates_intermediate_ca: "{{ lookup('op_document', 'intermediate-ca.pem', vault='FusionCloudX') }}"
certificates_server_cert: "{{ lookup('op_document', 'server-cert.pem', vault='FusionCloudX') }}"
certificates_server_key: "{{ lookup('op_document', 'server-key.pem', vault='FusionCloudX') }}"
```

### Optional Variables

```yaml
# Enable/disable CA installation
certificates_install_ca: true

# Enable/disable server certificate deployment
certificates_deploy_server: true

# Enable/disable nginx configuration
certificates_configure_nginx: false

# Certificate paths
certificates_ca_path: "/usr/local/share/ca-certificates"
certificates_cert_path: "/etc/ssl/certs"
certificates_key_path: "/etc/ssl/private"
```

## Dependencies

None.

## Example Playbook

```yaml
---
- hosts: all
  become: yes
  roles:
    - role: certificates
      certificates_install_ca: true
      certificates_deploy_server: true
```

## Integration with 1Password

Certificates are retrieved from 1Password during playbook execution:

```yaml
---
- hosts: all
  vars:
    certificates_root_ca: "{{ lookup('community.general.onepassword_raw', 'root-ca.pem', vault='FusionCloudX') }}"
  roles:
    - certificates
```

## License

MIT

## Author Information

Created for FusionCloudX Infrastructure deployment.
