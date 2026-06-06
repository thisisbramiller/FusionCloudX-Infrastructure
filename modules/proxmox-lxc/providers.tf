# Provider requirements only — NO provider config blocks. The root module that
# consumes this module supplies the configured `proxmox` provider.
terraform {
  required_version = ">= 1.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
  }
}
