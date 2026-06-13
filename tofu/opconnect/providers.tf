# ==============================================================================
# opconnect state — provider requirements + configs
# ==============================================================================
# SECRETS-ROOT STATE. opconnect provisions the VM that RUNS 1Password Connect, so
# it must apply WITHOUT depending on Connect (you cannot make Connect with Connect)
# and no SA token exists. There is intentionally NO onepassword provider here.
#
# Bootstrap trust (spec #68 / D6, D8): the Ansible keypair + the Connect seed live
# in the AWS off-site bundle (tmpx/onprem/opconnect-credentials, seeded by the
# `opconnect_credentials.yml` Ansible playbook). This state reads ONLY the recovery
# CMK by ALIAS + the NON-SECRET ansible public key for cloud-init (recovery.tf); the
# private key + Connect creds are read by ANSIBLE (amazon.aws.aws_secret), never by
# tofu -> never in state (#8). The read-only `aws` provider below assumes
# OrganizationAccountAccessRole into shared-services for those reads (the same path
# the S3 backend + state encryption already use).
#
# (Replaces the retired Option-D path: a local tls_private_key written to 1Password
# via the desktop `op` CLI. `tls` is dropped.)
# ==============================================================================
terraform {
  required_version = ">= 1.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
    unifi = {
      # Patched fork consumed via an OpenTofu filesystem mirror — see the
      # repo-root .tofurc and tofu/PATCHED-PROVIDER.md. Synthetic host +
      # pinned version; binary installed by scripts/build-unifi-provider.sh.
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
    aws = {
      # Read-only: the recovery CMK alias + the ephemeral public-key read
      # (recovery.tf). The S3 backend + state encryption already use AWS
      # (backend.tf / encryption.tf); this provider serves the data/ephemeral reads.
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.3.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  # Day-0 PKI delivers the node cert (bootstrap repo phases 04/13) — keep insecure=false.
  insecure = false

  ssh {
    agent    = true
    username = "terraform"
    # SSH_AUTH_SOCK environment variable is used automatically.
  }
}

provider "unifi" {
  # Bare controller URL ONLY — do NOT append /proxy/network or /api. The SDK
  # auto-discovers the UDM Pro /proxy/network path.
  api_url = "https://192.168.40.1"

  # The UDM Pro presents a self-signed certificate; skip TLS verification.
  allow_insecure = true

  # api_key is intentionally omitted — the provider reads it from the
  # UNIFI_API_KEY environment variable, keeping the secret out of HCL/state.
}

# Read-only AWS for the off-site-credentials reads (recovery.tf). Assumes
# OrganizationAccountAccessRole into shared-services (065094257518) — the same path
# the backend + state encryption use. No write paths in this state.
provider "aws" {
  region      = "us-east-2"
  max_retries = 10

  assume_role {
    role_arn     = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
    session_name = "tmpx-opconnect-read"
  }
}

provider "ansible" {}
