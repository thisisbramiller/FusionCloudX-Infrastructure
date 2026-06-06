output "id" {
  value       = onepassword_item.this.id
  description = "1Password item ID."
}

output "password" {
  value       = onepassword_item.this.password
  sensitive   = true
  description = "The generated password."
}
