# ==============================================================================
# network (foundation) state — input variables
# ==============================================================================

variable "proxmox_api_url" {
  type        = string
  default     = "https://192.168.40.206:8006/"
  description = "Proxmox VE API URL. Used by the proxmox provider that authors the foundation templates (ubuntu 9001 + debian LXC vztmpl)."
}
