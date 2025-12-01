terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.88.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://zero.fusioncloudx.home:8006/"
  insecure = true

  ssh {
    agent    = true
    username = "terraform"
  }
}