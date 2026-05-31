terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.0"
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
      source  = "ubiquiti-community/unifi"
      version = "0.41.25" # exact pin — rides an undocumented v2 API; revalidate after UniFi OS bumps
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
# Manages UniFi static DNS records on the UDM Pro (UniFi OS 5.1.12 / Network
# 10.3.58). The api_key is supplied via the UNIFI_API_KEY environment variable
# (sourced from Keychain/.zprofile, same posture as the proxmox SSH agent and
# the 1Password token) and is never committed.
# ==============================================================================

provider "unifi" {
  api_url        = "https://192.168.40.1" # UDM Pro; NO trailing /api
  allow_insecure = true                   # UDM ships a self-signed cert
  # api_key  -> UNIFI_API_KEY env var
}

