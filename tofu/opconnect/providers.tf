# ==============================================================================
# opconnect state — provider requirements + configs
# ==============================================================================
# SECRETS-ROOT STATE. opconnect provisions the VM that RUNS 1Password Connect,
# so it must apply WITHOUT depending on Connect (you cannot make Connect with
# Connect) and no SA token exists. There is therefore intentionally NO
# onepassword provider here: the Ansible SSH keypair is generated locally
# (tls_private_key) and written to 1Password via the desktop `op` CLI in account
# mode (ssh-keys.tf), which needs neither Connect nor an SA token. Day-2 secret
# consumption happens later in tofu/compute + ansible, via Connect.
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
    tls = {
      # Re-added: opconnect OWNS the Ansible SSH keypair (ssh-keys.tf generates it
      # via tls_private_key and writes both halves to 1Password). The redesign had
      # dropped hashicorp/tls assuming a bootstrap seeder that was never built.
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

# NOTE: no `provider "onepassword"` here by design — opconnect must apply
# Connect-free. The Ansible SSH keypair is written to 1Password out-of-band via
# the desktop `op` CLI (see ssh-keys.tf + scripts/op-write-ssh-key.sh).

provider "ansible" {}
