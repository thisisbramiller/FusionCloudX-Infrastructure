terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.88.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  # TODO: Set up proper SSL certificates for production. See README for details.
  insecure = true

  ssh {
    agent    = true
    username = "terraform"
  }
}