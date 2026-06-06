variable "name" {
  type        = string
  description = "Guest name. Used for the cloud-init hostname and the snippet file names."
}

variable "ansible_pubkey" {
  type        = string
  description = "Ansible SSH public key (OpenSSH format) authorized for the ansible user."
}

variable "datastore_id" {
  type        = string
  default     = "nas-infrastructure"
  description = "Datastore that holds the cloud-init snippets."
}

variable "packages" {
  type = list(string)
  default = [
    "qemu-guest-agent",
    "net-tools",
    "curl",
    "python3",
    "python3-pip",
  ]
  description = "Base packages installed by vendor-data. Python is required for Ansible on every VM."
}

variable "extra_packages" {
  type        = list(string)
  default     = []
  description = "Additional packages appended to the base set (e.g. GitLab prerequisites)."
}

variable "runcmd" {
  type = list(string)
  default = [
    "systemctl enable qemu-guest-agent",
    "systemctl start qemu-guest-agent",
  ]
  description = "Commands run by vendor-data (cloud-config runcmd entries)."
}

variable "fqdn" {
  type        = string
  default     = null
  description = "Optional fully-qualified domain name set in vendor-data (e.g. gitlab.fusioncloudx.home)."
}

variable "package_upgrade" {
  type        = bool
  default     = false
  description = "Whether vendor-data runs a full package upgrade."
}

variable "debconf_selections" {
  type        = string
  default     = null
  description = "Optional debconf selections block for non-interactive package config (e.g. postfix)."
}
