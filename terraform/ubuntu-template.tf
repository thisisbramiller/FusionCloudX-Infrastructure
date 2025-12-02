resource "proxmox_virtual_environment_vm" "ubuntu-template" {
  name      = "ubuntu-template"
  node_name = "zero"

  started  = false
  tags     = ["template", "ubuntu"]
  bios     = "seabios"
  template = true

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
    iothread = true
    import_from = proxmox_virtual_environment_download_file.ubuntu-cloud-image.id
    size = 32
  }

  serial_device {}

}

resource "proxmox_virtual_environment_download_file" "ubuntu-cloud-image" {
    node_name = "zero"
    datastore_id = "nas-infrastructure"
    content_type = "import"
    url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

    file_name = "noble-server-cloudimg-amd64.qcow2"
}

