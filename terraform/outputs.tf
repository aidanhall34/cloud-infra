output "gateway_public_ip" {
  description = "Public IPv4 address of the gateway — use as the WireGuard endpoint in MikroTik"
  value       = linode_instance.gateway.ip_address
}

output "gateway_id" {
  description = "Linode ID of the gateway instance"
  value       = linode_instance.gateway.id
}
