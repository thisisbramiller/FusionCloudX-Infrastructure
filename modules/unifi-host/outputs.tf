output "dns_name" {
  value       = unifi_dns_record.this.name
  description = "The published A-record FQDN (<name>.fusioncloudx.home)."
}

output "ip" {
  value       = unifi_dns_record.this.value
  description = "The pinned/published IPv4 address."
}
