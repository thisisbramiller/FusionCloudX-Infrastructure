resource "proxmox_virtual_environment_vm" "ubuntu-template" {
  name      = "ubuntu-template"
  node_name = "zero"

  started  = false
  tags     = ["template", "ubuntu"]
  bios     = "seabios"
  template = true

  initialization {
    datastore_id = "vm-data"
    interface = "scsi0"
    file_format  = "qcow2"
    
    user_account {
      username = "fcx"
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

  }

  serial_device {}
#   disk {
#     datastore_id = "vm-data"
#     interface    = "virtio0"
#   }
}

