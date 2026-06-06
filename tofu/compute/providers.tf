# ==============================================================================
# compute state — provider requirements + configs
# ==============================================================================
# A3 single compute state: per-service files call the thin modules in
# ../../modules/. AWS is ONLY the state backend + state-encryption key provider
# (see backend.tf / encryption.tf) — there is intentionally NO aws provider here.
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
      # repo-root .tofurc and terraform/PATCHED-PROVIDER.md. Synthetic host +
      # pinned version; binary installed by scripts/build-unifi-provider.sh.
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
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

# 1Password provider: authenticated via environment (OP_SERVICE_ACCOUNT_TOKEN,
# or OP_CONNECT_HOST/OP_CONNECT_TOKEN for the on-prem Connect server). No
# secrets in HCL/state.
provider "onepassword" {}

provider "ansible" {}
