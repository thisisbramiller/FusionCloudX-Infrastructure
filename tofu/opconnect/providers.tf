# ==============================================================================
# opconnect state — provider requirements + configs
# ==============================================================================
# SECRETS-ROOT STATE. opconnect is the secrets root of the on-prem estate: it
# creates the VM that RUNS 1Password Connect. Therefore it CANNOT authenticate
# to 1Password via Connect (you cannot make Connect with Connect) — the
# onepassword provider here authenticates with the **Service Account token**
# (OP_SERVICE_ACCOUNT_TOKEN + the `op` CLI), the bootstrap auth path. The actual
# Connect server/token bring-up + cutover is P4; this state only AUTHORS the
# VM + DNS + ansible targeting that the P4 role then provisions.
#
# As with tofu/compute, AWS is ONLY the state backend + state-encryption key
# provider (see backend.tf / encryption.tf) — there is intentionally NO aws
# provider here.
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

# 1Password provider — auto-detects auth from the environment.
# P4 cutover: reads the single Ansible-SSH-key item via the OLD Connect
# (OP_CONNECT_HOST + OP_CONNECT_TOKEN in env). A from-scratch rebuild would
# instead supply OP_SERVICE_ACCOUNT_TOKEN or run `op signin` to restage
# credentials. No secrets in HCL/state.
provider "onepassword" {}

provider "ansible" {}
