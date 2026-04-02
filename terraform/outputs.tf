output "gateway_public_ip" {
  description = "Public IP of vm-gateway. Use this as the WireGuard endpoint in MikroTik."
  value       = oci_core_instance.gateway.public_ip
}

output "telemetry_public_ip" {
  description = "Public IP of vm-telemetry (SSH access only)."
  value       = oci_core_instance.telemetry.public_ip
}

output "gateway_private_ip" {
  description = "Dynamically assigned private IP of vm-gateway (changes on recreation — use OCI VCN DNS for stable routing)."
  value       = oci_core_instance.gateway.private_ip
}

output "telemetry_private_ip" {
  description = "Dynamically assigned private IP of vm-telemetry (changes on recreation — use OCI VCN DNS for stable routing)."
  value       = oci_core_instance.telemetry.private_ip
}

output "wireguard_gateway_public_key" {
  description = "WireGuard public key for vm-gateway. Use this as the peer public key in MikroTik. Also stored in secrets/wireguard_gateway_public.key."
  value       = trimspace(file("${path.root}/../secrets/wireguard_gateway_public.key"))
}

output "next_steps" {
  description = "Manual steps required after terraform apply."
  value       = <<-EOT

    ── Post-deployment checklist ────────────────────────────────────────────

    1. Wait ~10 minutes for cloud-init to finish on both VMs.
       Monitor progress: ssh ubuntu@${oci_core_instance.gateway.public_ip} 'sudo tail -f /var/log/cloud-init-output.log'

    2. Retrieve the WireGuard public key from vm-gateway:
       ssh ubuntu@${oci_core_instance.gateway.public_ip} 'sudo cat /etc/wireguard/public.key'

    3. Configure MikroTik WireGuard peer using that public key.
       Endpoint: ${oci_core_instance.gateway.public_ip}:51820
       Peer IP:  10.10.0.2/32  (or whatever you set in AllowedIPs)
       Or run:  make mikrotik

    4. Add the MikroTik public key to vm-gateway:
       ssh ubuntu@${oci_core_instance.gateway.public_ip}
       sudo wg set wg0 peer <mikrotik-pubkey> allowed-ips 10.10.0.2/32
       sudo wg-quick save wg0

    5. Verify Blocky DNS is running:
       ssh ubuntu@${oci_core_instance.gateway.public_ip} 'sudo systemctl status blocky'
       dig @${oci_core_instance.gateway.public_ip} example.com

    6. Access Grafana via WireGuard:
       http://${local.telemetry_internal_hostname}:3000

    ─────────────────────────────────────────────────────────────────────────
  EOT
}
