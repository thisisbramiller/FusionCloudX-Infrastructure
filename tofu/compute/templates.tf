# ==============================================================================
# Templates — clone sources for the compute fleet (Scheme B 9xxx)
# ==============================================================================
# - ubuntu-template (VM 9001): the full-clone source for every QEMU guest. The
#   proxmox-vm module defaults template_vm_id = 9001, so service files clone
#   from this without passing template_vm_id explicitly.
# - debian-12 LXC template: a download_file (no VMID); the proxmox-lxc module
#   references it by .id (passed via template_file_id in postgresql.tf).
#
# Renumbered from the flat config (ubuntu-template was VMID 1000) to the
# greenfield Scheme B template band (9xxx). OS disk on local-zfs per the
# greenfield storage lock; the cloud image + LXC template downloads land on
# nas-infrastructure (same as the flat config).
# ==============================================================================

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  node_name    = "pve"
  datastore_id = "nas-infrastructure"
  content_type = "import"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

  file_name = "noble-server-cloudimg-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name      = "ubuntu-template"
  node_name = "pve"
  vm_id     = 9001

  started  = false
  tags     = ["template", "ubuntu"]
  bios     = "seabios"
  template = true

  boot_order = ["scsi1"]

  initialization {
    datastore_id = "local-zfs"
    interface    = "scsi0"

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
    datastore_id = "local-zfs"
    interface    = "scsi1"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    size         = 32
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

# Debian 12 standard LXC template. No VMID — the proxmox-lxc module consumes its
# .id via template_file_id (see postgresql.tf).
resource "proxmox_virtual_environment_download_file" "debian12_lxc_template" {
  node_name    = "pve"
  content_type = "vztmpl"
  datastore_id = "nas-infrastructure"

  url = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"

  overwrite           = true
  overwrite_unmanaged = false
}
