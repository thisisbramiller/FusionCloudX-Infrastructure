terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.88.0"
    }
  }
}

variable proxmox_api_url {
    type = string
    default = "https://zero.fusioncloudx.home:8006/"
    description = "Proxmox VE API URL"
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true

  ssh {
    agent    = true
    username = "terraform"
  }
}