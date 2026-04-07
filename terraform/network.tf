# Firewall — attached directly to the gateway instance.
#
# Inbound policy: DROP everything except traffic from var.allowed_ip_range.
# Outbound policy: ACCEPT all.

resource "linode_firewall" "gateway" {
  label = "gateway"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "1-65535"
    ipv4     = [var.allowed_ip_range]
  }

  inbound {
    label    = "allow-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "1-65535"
    ipv4     = [var.allowed_ip_range]
  }

  inbound {
    label    = "allow-icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = [var.allowed_ip_range]
  }

  linodes = [linode_instance.gateway.id]
}
