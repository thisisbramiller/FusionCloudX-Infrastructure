resource "proxmox_virtual_environment_vm" "ubuntu-template" {
  name      = "ubuntu-template"
  node_name = "zero"
  vm_id = 1000

  started  = false
  tags     = ["template", "ubuntu"]
  bios     = "seabios"
  template = true

  boot_order = ["scsi1"]

  initialization {
    datastore_id = "vm-data"
    interface    = "scsi0"
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

  disk {
    datastore_id = "vm-data"
    interface    = "scsi1"
    import_from = proxmox_virtual_environment_download_file.ubuntu-cloud-image.id
    size = 32
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  cpu {
    type = "x86-64-v2-AES"
  }

  network_device {
    bridge = "vmbr0"
  }

}

resource "proxmox_virtual_environment_download_file" "ubuntu-cloud-image" {
    node_name = "zero"
    datastore_id = "nas-infrastructure"
    content_type = "import"
    url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    
    file_name = "noble-server-cloudimg-amd64.qcow2"
}

