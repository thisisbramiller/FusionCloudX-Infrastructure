# FusionCloudX Infrastructure

Infrastructure as Code (IaC) for managing virtual machines on Proxmox Virtual Environment using Terraform and Ansible.

## Overview

This repository automates the provisioning and configuration of Ubuntu VMs on Proxmox VE. It uses Terraform to create VM templates from Ubuntu cloud images and provision VMs, then uses Ansible for post-deployment configuration management.

## Prerequisites

### Required Software

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.9
- SSH client with agent support
- Access to a Proxmox VE cluster

### Proxmox Requirements

- Proxmox VE node named `pve` (or update configurations accordingly)
- User account named `terraform` with appropriate API permissions
- SSH access configured for the `terraform` user
- Two datastores:
  - `nas-infrastructure` - For cloud images and snippets
  - `vm-data` - For VM disks
- Network bridge `vmbr0` configured

### SSH Setup

Ensure your SSH agent is running and has the key for the `terraform` user:

```bash
# Start SSH agent (if not running)
eval "$(ssh-agent -s)"

# Add your SSH key
ssh-add ~/.ssh/your_proxmox_key

# Verify the key is loaded
ssh-add -l
```

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd "FusionCloudX Infrastructure"
```

### 2. Configure Terraform

Update `terraform/provider.tf` if your Proxmox API URL differs:

```hcl
variable proxmox_api_url {
    default = "https://your-proxmox-host:8006/"
}
```

### 3. Initialize and Apply Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will:
1. Download the Ubuntu Noble cloud image
2. Create a VM template (ID 1000)
3. Clone the template to create a VM named `test-vm`
4. Configure the VM with cloud-init

### 4. Get VM IP Address

```bash
terraform output vm_ipv4_address
```

### 5. Configure with Ansible

Update the Ansible inventory with your VM's IP address:

```bash
cd ../ansible
# Edit inventory/hosts.ini to add your VM
ansible-playbook playbooks/site.yml
```

## Project Structure

```
.
├── terraform/              # Terraform configurations
│   ├── provider.tf        # Proxmox provider setup
│   ├── backend.tf         # State backend configuration
│   ├── variables.tf       # Variable definitions
│   ├── ubuntu-template.tf # VM template creation
│   ├── cloud-init.tf      # Cloud-init configuration
│   ├── main.tf            # VM resource definitions
│   └── outputs.tf         # Output values
│
├── ansible/               # Ansible configurations
│   ├── ansible.cfg        # Ansible configuration
│   ├── inventory/         # Inventory files
│   │   └── hosts.ini      # Host definitions
│   ├── group_vars/        # Group variables
│   │   └── all.yml        # Global variables
│   ├── playbooks/         # Playbook definitions
│   │   └── site.yml       # Main playbook
│   └── roles/             # Ansible roles
│       └── common/        # Common configuration role
│
└── README.md              # This file
```

## Configuration

### Cloud-Init

The default cloud-init configuration (`terraform/cloud-init.tf`):

- **Hostname:** test
- **Timezone:** America/Chicago
- **User:** fcx (sudo access, password authentication disabled)
- **SSH Keys:** Imported from GitHub user `thisisbramiller`
- **Packages:** qemu-guest-agent, net-tools, curl

To customize, edit `terraform/cloud-init.tf` and modify the cloud-config data.

### VM Specifications

Default VM configuration (`terraform/main.tf`):

- **CPU:** 4 cores (x86-64-v2-AES)
- **Memory:** 2048 MB
- **Disk:** 32 GB (inherited from template)
- **Network:** DHCP on vmbr0
- **BIOS:** SeaBIOS

### Ansible Configuration

The `common` role (`ansible/roles/common/tasks/main.yml`):

- Updates apt cache
- Installs nginx
- Creates user `fusionuser` with sudo access
- Ensures nginx service is running

## Common Operations

### Creating Additional VMs

1. Duplicate the VM resource block in `terraform/main.tf`
2. Change the VM name and adjust specifications as needed
3. Run `terraform apply`

Example:

```hcl
resource "proxmox_virtual_environment_vm" "web_server" {
  name      = "web-server-01"
  node_name = "pve"
  started   = true

  clone {
    vm_id = 1000
    full  = true
  }

  # ... rest of configuration
}
```

### Updating the Template

To update the template with a newer Ubuntu image:

1. The template will be recreated with the latest image URL specified in `ubuntu-template.tf`
2. Run `terraform apply` to update

### Destroying Resources

```bash
cd terraform

# Destroy specific resource
terraform destroy -target=proxmox_virtual_environment_vm.test_vm

# Destroy all resources
terraform destroy
```

**Warning:** Destroying the template will affect all cloned VMs.

## Troubleshooting

### Terraform Authentication Issues

If Terraform cannot connect to Proxmox:

- Verify SSH agent is running: `ssh-add -l`
- Test SSH connection: `ssh terraform@192.168.40.206`
- Check Proxmox user permissions

### VM Not Getting IP Address

- Ensure QEMU guest agent is running in the VM
- Check that the VM has network connectivity
- Verify DHCP is working on your network
- Wait a few moments after VM creation for the agent to start

### Cloud-Init Not Applying

- Check cloud-init logs in the VM: `sudo cat /var/log/cloud-init.log`
- Verify the cloud-init file exists in Proxmox under Datacenter → Storage → nas-infrastructure
- Ensure the datastore has permission to store snippets

## Security Notes

- The Proxmox provider uses `insecure = true` for TLS verification. For production, configure proper certificates.
- SSH keys are imported from a public GitHub profile. Ensure this is appropriate for your security requirements.
- The `fcx` user has passwordless sudo access. Review this for production environments.
- Terraform state contains sensitive information. Do not commit `terraform.tfstate` to version control.

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Test thoroughly with `terraform plan`
4. Submit a pull request to `main`

## License

[Specify your license here]

## Support

For issues or questions, please open an issue in this repository.

## Certificate Management

### Overview

FusionCloudX Infrastructure integrates with the bootstrap repository for certificate deployment. Certificates are generated during disaster recovery (bootstrap Phase 04) and deployed to VMs during infrastructure provisioning.

### Certificate Flow

```
┌─────────────────────────────────────────┐
│   Bootstrap Repository (Phase 04)       │
│   - Generate Root CA                    │
│   - Generate Intermediate CA            │
│   - Generate Server Certificate         │
│   - Store in 1Password                  │
└─────────────────────────────────────────┘
                    │
                    ↓ (1Password)
┌─────────────────────────────────────────┐
│   Infrastructure Repository (Ansible)   │
│   - Retrieve certificates from 1Pass    │
│   - Deploy to VMs (certificates role)   │
│   - Configure services (nginx, etc.)    │
└─────────────────────────────────────────┘
```

### Usage

**Test Certificate Deployment:**
```bash
ansible-playbook ansible/playbooks/test-certificates.yml --limit gitlab
```

**Deploy Certificates to All Hosts:**
```bash
ansible-playbook ansible/playbooks/site.yml --tags certificates
```

**Deploy Certificates to Specific Host:**
```bash
ansible-playbook ansible/playbooks/common.yml --limit gitlab
```

### Troubleshooting

**Issue: "Certificate deployment failed"**
- Verify 1Password CLI authentication: `op vault list`
- Check bootstrap repository Phase 04 completed successfully
- Verify certificates exist in 1Password vault "FusionCloudX"

**Issue: "CA not in trust store"**
- Run: `sudo update-ca-certificates`
- Verify CA file exists: `ls /usr/local/share/ca-certificates/fusioncloudx-*.crt`

See `ansible/roles/certificates/README.md` for detailed configuration options.

## Additional Documentation

- **Certificate Management:** See `ansible/roles/certificates/README.md` for role details
- **Optional Device Certificates:** See `docs/DEVICE-CERTIFICATE-DEPLOYMENT.md`
- **Control Plane Architecture:** See `docs/CONTROL-PLANE.md`
- **Bootstrap Integration:** Certificates generated by `fusioncloudx-bootstrap` repository (Phase 04)

---

**Last Updated:** 2026-02-02
**Bootstrap Integration:** This repository integrates with fusioncloudx-bootstrap for PKI and certificate management
**Architecture:** Control Plane-based infrastructure using GitLab CI/CD for automation orchestration
- **Bootstrap Integration:** Certificates generated by `fusioncloudx-bootstrap` repository (Phase 04)

---

**Last Updated:** 2026-01-28
**Bootstrap Integration:** This repository integrates with fusioncloudx-bootstrap for PKI and certificate management
**Architecture:** Control Plane-based infrastructure using GitLab CI/CD for automation orchestration
>>>>>>> origin/main
