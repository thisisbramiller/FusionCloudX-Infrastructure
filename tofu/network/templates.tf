# ==============================================================================
# Templates — clone sources for the compute fleet (Scheme B 9xxx)
# ==============================================================================
# FOUNDATION: templates live in network/ (the FIRST-applied state, P3) so they
# physically exist on the pve node before opconnect (P4) and compute (P5) clone
# from them. Moved here from tofu/compute/templates.tf precisely so the phase
# order P3 (network) -> P4 (opconnect) -> P5 (compute) never tries to clone a
# template that has not been created yet.
#
# - ubuntu-template (VM 9001): the full-clone source for every QEMU guest. The
#   proxmox-vm module defaults template_vm_id = 9001, so service files clone
#   from this; opconnect + compute pass it explicitly from this state's outputs.
# - debian-12 LXC template: a download_file (no VMID); the proxmox-lxc module
#   references it by .id (passed via template_file_id in compute/postgresql.tf).
#
# CROSS-STATE CLONE SAFETY: opconnect/ and compute/ clone by vm_id (9001) — a
# value, not a managed resource reference. That is safe ONLY because network/
# applies first (P3) and physically creates 9001 on the pve node before P4/P5
# run. The phase order is the contract; do not reorder.
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

  # The cloud image already exists on nas-infrastructure (downloaded by the flat
  # config). overwrite_unmanaged = true lets this state ADOPT the pre-existing
  # file instead of erroring "refusing to override existing file"; overwrite =
  # false skips size-based re-download once the file is managed (adopt-if-
  # unmanaged, don't clobber-if-managed).
  overwrite           = false
  overwrite_unmanaged = true
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
# .id via template_file_id (see compute/postgresql.tf).
resource "proxmox_virtual_environment_download_file" "debian12_lxc_template" {
  node_name    = "pve"
  content_type = "vztmpl"
  datastore_id = "nas-infrastructure"

  url = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"

  # The vztmpl already exists on nas-infrastructure (downloaded by the flat
  # config). overwrite_unmanaged = true lets this state ADOPT the pre-existing
  # file instead of erroring "refusing to override existing file"; overwrite =
  # false skips size-based re-download once the file is managed (adopt-if-
  # unmanaged, don't clobber-if-managed).
  overwrite           = false
  overwrite_unmanaged = true
}
