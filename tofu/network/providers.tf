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
  }
}

# AWS is only the state backend + state-encryption key provider — NO aws
# provider block here. network/ is the FOUNDATION state: it authors the UniFi
# network data lookups (stable id) AND the proxmox templates (9001 + the debian
# LXC vztmpl) so they exist before opconnect (P4) and compute (P5) clone them.

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
