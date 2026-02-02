# ==============================================================================
# Debian 12 LXC Template Download
# ==============================================================================
# Downloads the standard Debian 12 LXC template for container creation
# Hook script handles package installation after container starts
# ==============================================================================

resource "proxmox_virtual_environment_download_file" "debian12_lxc_template" {
  node_name    = "pve"
  content_type = "vztmpl"
  datastore_id = "nas-infrastructure"

  url = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"

  overwrite           = true
  overwrite_unmanaged = false
}
