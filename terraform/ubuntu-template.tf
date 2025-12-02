resource "proxmox_virtual_environment_vm" "ubuntu-template" {
  name      = "ubuntu-template"
  node_name = "zero"

  started  = false
  tags     = ["template", "ubuntu"]
  bios     = "seabios"
  template = true

  initialization {
    user_account {
      username = "fcx"
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}
