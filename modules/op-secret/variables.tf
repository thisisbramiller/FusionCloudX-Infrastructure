variable "vault" {
  type        = string
  description = "1Password vault ID that holds the item."
}

variable "title" {
  type        = string
  description = "Item title (Ansible references items by title, not resource name)."
}

variable "category" {
  type        = string
  default     = "password"
  description = "1Password item category (e.g. password, login, database)."
}

variable "length" {
  type        = number
  default     = 32
  description = "Generated password length."
}

variable "symbols" {
  type        = bool
  default     = false
  description = "Whether the generated password includes symbols."
}

variable "note_value" {
  type        = string
  default     = ""
  description = "Static provenance / notes for the item (NO timestamp — keep it static so apply is a no-op)."
}

variable "tags" {
  type        = list(string)
  default     = []
  description = "Tags applied to the item."
}

variable "username" {
  type        = string
  default     = null
  description = "Optional username stored on the item."
}
