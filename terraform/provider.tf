terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    unifi = {
      # Patched fork consumed via a Terraform filesystem mirror -- see
      # terraform/PATCHED-PROVIDER.md. Synthetic host + pinned version;
      # binary installed by scripts/build-unifi-provider.sh.
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  # TODO: Set up proper SSL certificates for production. See README for details.
  insecure = false

  ssh {
    agent    = true
    username = "terraform"
    # SSH_AUTH_SOCK environment variable is used automatically
  }
}

# ==============================================================================
# 1Password Provider Configuration
# ==============================================================================
# The 1Password provider requires either:
#   1. OP_SERVICE_ACCOUNT_TOKEN environment variable (recommended for automation)
#   2. OP_CONNECT_HOST and OP_CONNECT_TOKEN for self-hosted Connect server
# See 1PASSWORD_SETUP.md for detailed configuration instructions
# ==============================================================================

provider "onepassword" {
  # Authentication is handled via environment variables:
  # - OP_SERVICE_ACCOUNT_TOKEN (for service account authentication)
  # OR
  # - OP_CONNECT_HOST and OP_CONNECT_TOKEN (for 1Password Connect)
  #
  # For service account (recommended for homelab):
  #   export OP_SERVICE_ACCOUNT_TOKEN="your-service-account-token"
  #
  # For 1Password Connect (more advanced):
  #   export OP_CONNECT_HOST="http://localhost:8080"
  #   export OP_CONNECT_TOKEN="your-connect-token"
}

# ==============================================================================
# UniFi Provider Configuration (ubiquiti-community/unifi)
# ==============================================================================
# Manages DHCP fixed-IP reservations and local DNS records on the UDM Pro
# controller (VLAN 40 "Home Lab"). Authentication uses an API key sourced
# ENTIRELY from the environment so the secret never lands in HCL or state:
#   export UNIFI_API_KEY="your-udm-pro-api-key"
#
# Note: the env var for the controller URL is UNIFI_API (NOT UNIFI_API_URL),
# and the TLS-skip env var is UNIFI_INSECURE (the HCL arg is allow_insecure).
#
# PATCHED PROVIDER REQUIRED: stock v0.41.25 is broken on UniFi OS 5.x / Network
# App 10.x -- unifi_client adopt fails with "inconsistent result after apply
# (.fixed_ip null)" (issue #138), and parallel reads crash on a logging map race
# (ported PR #168). This deployment consumes a maintained fork
# (thisisbramiller/terraform-provider-unifi, branch `patches`) built into a
# Terraform filesystem mirror and pinned by .terraform.lock.hcl (h1:) -- NOT
# dev_overrides. Build with scripts/build-unifi-provider.sh.
# See terraform/PATCHED-PROVIDER.md.
# ==============================================================================

provider "unifi" {
  # Bare controller URL ONLY -- do NOT append /proxy/network or /api.
  # The SDK auto-discovers the UDM Pro /proxy/network path.
  api_url = "https://192.168.40.1"

  # The UDM Pro presents a self-signed certificate; skip TLS verification.
  allow_insecure = true

  # api_key is intentionally omitted -- the provider reads it from the
  # UNIFI_API_KEY environment variable, keeping the secret out of HCL/state.
  # site defaults to "default"; omitted because we manage the default site.
}

