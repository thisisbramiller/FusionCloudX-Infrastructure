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
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  # TODO: Set up proper SSL certificates for production. See README for details.
  insecure = false

  ssh {
    agent    = true
    username = "terraform"
    agent_socket = "/Users/fcx/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
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