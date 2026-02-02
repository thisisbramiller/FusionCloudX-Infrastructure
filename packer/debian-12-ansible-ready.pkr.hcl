# ==============================================================================
# Packer Template: Ansible-Ready Debian 12 LXC
# ==============================================================================
# Builds a custom Debian 12 LXC template with Ansible prerequisites pre-installed
#
# Prerequisites:
#   - Run on packer-builder VM with LXC tools installed
#   - Packer LXC plugin installed
#
# Usage:
#   packer init debian-12-ansible-ready.pkr.hcl
#   packer validate debian-12-ansible-ready.pkr.hcl
#   packer build debian-12-ansible-ready.pkr.hcl
#
# Output:
#   /var/lib/vz/template/cache/debian-12-ansible-ready.tar.gz
# ==============================================================================

packer {
  required_plugins {
    lxc = {
      source  = "github.com/hashicorp/lxc"
      version = "~> 1"
    }
  }
}

# ==============================================================================
# Variables
# ==============================================================================

variable "output_dir" {
  type        = string
  default     = "/var/lib/vz/template/cache"
  description = "Directory where the template will be created"
}

variable "template_name" {
  type        = string
  default     = "debian-12-ansible-ready"
  description = "Name of the output template (without extension)"
}

variable "debian_release" {
  type        = string
  default     = "bookworm"
  description = "Debian release codename"
}

# ==============================================================================
# Source: LXC Container
# ==============================================================================

source "lxc" "debian-12-ansible-ready" {
  config_file      = "/etc/lxc/default.conf"
  template_name    = "debian"
  template_parameters = [
    "--release", var.debian_release,
    "--arch", "amd64"
  ]
  output_directory = var.output_dir
}

# ==============================================================================
# Build Pipeline
# ==============================================================================

build {
  sources = ["source.lxc.debian-12-ansible-ready"]

  # Provision the container with Ansible prerequisites
  provisioner "shell" {
    script = "scripts/provision-ansible-ready.sh"
  }

  # Create compressed template archive
  post-processor "compress" {
    output = "${var.output_dir}/${var.template_name}.tar.gz"
  }
}
