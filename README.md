# FusionCloudX Infrastructure

Infrastructure as Code (IaC) for managing virtual machines on Proxmox Virtual Environment using OpenTofu and Ansible.

## Overview

This repository automates the provisioning and configuration of Ubuntu VMs on Proxmox VE. It uses OpenTofu to create VM templates from Ubuntu cloud images and provision VMs, then uses Ansible for post-deployment configuration management.

## Prerequisites

### Required Software

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6
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

### 2. Configure OpenTofu

Update `tofu/network/provider.tf` if your Proxmox API URL differs:

```hcl
variable proxmox_api_url {
    default = "https://your-proxmox-host:8006/"
}
```

### 3. Initialize and Apply OpenTofu

The infrastructure is split into three independent state directories. Apply them
**in order** — `compute` reads outputs from `network`, so `network` must exist first:

```bash
for s in network opconnect compute; do
  tofu -chdir=tofu/$s init
  tofu -chdir=tofu/$s apply
done
```

This will:
1. Download the Ubuntu Noble cloud image
2. Create a VM template (ID 9001)
3. Stand up the 1Password Connect singleton (opconnect)
4. Provision the per-service VMs and configure them with cloud-init

### 4. Get VM IP Address

```bash
(cd tofu/compute && tofu output infrastructure_summary)
```

### 5. Configure with Ansible

The Ansible inventory is dynamic (the `cloud.terraform` plugin reads `tofu/compute` state), so there are no host files to edit:

```bash
cd ansible
ansible-playbook -i inventory/terraform.yml playbooks/site.yml
```

## Project Structure

```
.
├── tofu/                   # OpenTofu configurations (3 independent states)
│   ├── network/           # State 1: template, bridges, DNS, network outputs
│   │   ├── provider.tf    # Proxmox provider setup
│   │   ├── backend.tf     # S3 + SSE-KMS remote state backend
│   │   ├── variables.tf   # Variable definitions
│   │   ├── templates.tf   # VM template creation (ID 9001)
│   │   └── outputs.tf     # Network outputs consumed by compute
│   ├── opconnect/         # State 2: 1Password Connect singleton
│   │   ├── backend.tf     # S3 + SSE-KMS remote state backend
│   │   └── opconnect.tf   # prevent_destroy Connect resources
│   ├── compute/           # State 3: per-service VMs (reads network outputs)
│   │   ├── backend.tf     # S3 + SSE-KMS remote state backend
│   │   ├── gitlab.tf      # GitLab VM (prevent_destroy singleton)
│   │   ├── postgresql.tf  # PostgreSQL VM (prevent_destroy singleton)
│   │   ├── <svc>.tf       # One file per service VM
│   │   └── outputs.tf     # infrastructure_summary output
│   └── PATCHED-PROVIDER.md # Why the UniFi provider is vendored/patched
│
├── modules/                # Thin reusable OpenTofu modules
│   ├── proxmox-vm/        # VM (protected + disposable variants)
│   ├── proxmox-lxc/       # Unprivileged LXC (PostgreSQL)
│   ├── cloud-init/        # Cloud-init snippet
│   └── unifi-host/        # UniFi client reservation + DNS record
│
├── ansible/               # Ansible configurations
│   ├── ansible.cfg        # Ansible configuration
│   ├── inventory/         # Dynamic inventory (cloud.terraform plugin)
│   │   └── terraform.yml  # Reads ../tofu/compute state for hosts
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

The default cloud-init configuration (`modules/cloud-init/main.tf`):

- **Hostname:** test
- **Timezone:** America/Chicago
- **User:** fcx (sudo access, password authentication disabled)
- **SSH Keys:** Imported from GitHub user `thisisbramiller`
- **Packages:** qemu-guest-agent, net-tools, curl

To customize, edit `modules/cloud-init/main.tf` and modify the cloud-config data.

### VM Specifications

Default VM configuration (per-service `tofu/compute/<svc>.tf`):

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

1. Add a new `tofu/compute/<svc>.tf` file that calls the `vm` module
2. Set the service name and override any specs as needed
3. Run `tofu -chdir=tofu/compute apply`

Example:

```hcl
module "web_server" {
  source = "../../modules/proxmox-vm"

  name      = "web-server-01"
  node_name = "pve"

  template_vm_id = 9001
  network        = data.terraform_remote_state.network.outputs

  # ... per-service overrides (cpu, memory, disk)
}
```

### Updating the Template

To update the template with a newer Ubuntu image:

1. The template will be recreated with the latest image URL specified in `tofu/network/templates.tf`
2. Run `tofu -chdir=tofu/network apply` to update

### Destroying Resources

Tear down in **reverse** apply order (`compute` first, `network` last) so that
`compute` is gone before the `network` outputs it depends on:

```bash
for s in compute opconnect network; do
  tofu -chdir=tofu/$s destroy
done
```

**Warning:** The `gitlab`, `postgresql`, and `opconnect` resources are
`prevent_destroy` singletons — `tofu destroy` will error on them by design.
Remove the `prevent_destroy` lifecycle block (or `-target` around them)
deliberately before tearing those down. Destroying the template will affect
all cloned VMs.

## Troubleshooting

### OpenTofu Authentication Issues

If OpenTofu cannot connect to Proxmox:

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

- The Proxmox provider uses `insecure = false` for TLS verification. The Day-0 PKI flow delivers the node certificate, so the provider validates against the FusionCloudX CA.
- SSH keys are imported from a public GitHub profile. Ensure this is appropriate for your security requirements.
- The `fcx` user has passwordless sudo access. Review this for production environments.
- State lives in a remote S3 backend with SSE-KMS encryption at rest, not on disk. There is no `terraform.tfstate` to commit — never commit local state or `.tfstate` files if one is ever generated.

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Test thoroughly with `tofu plan`
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
- **Bootstrap Integration:** Certificates generated by `fusioncloudx-bootstrap` repository (Phase 04)

---

**Last Updated:** 2026-06-12
**Bootstrap Integration:** This repository integrates with fusioncloudx-bootstrap for PKI and certificate management
**Architecture:** Control Plane-based infrastructure using GitLab CI/CD for automation orchestration
