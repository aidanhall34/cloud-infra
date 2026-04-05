data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
}

# --- VCN ---

resource "oci_core_vcn" "homelab" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "homelab-vcn"
  dns_label      = "homelab"
}

resource "oci_core_internet_gateway" "homelab" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "homelab-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.homelab.id
  }
}

# --- Security lists ---

resource "oci_core_security_list" "gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "gateway-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # SSH
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # WireGuard
  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"
    udp_options {
      min = var.wireguard_port
      max = var.wireguard_port
    }
  }

}

resource "oci_core_security_list" "telemetry" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "telemetry-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # SSH (public — restrict to your IP in production)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # All traffic from within the VCN (otelcol metrics/logs/traces from gateway → telemetry)
  ingress_security_rules {
    protocol = "all"
    source   = var.vcn_cidr
  }

  # All traffic from the WireGuard VPN overlay (Grafana/dashboard access via VPN)
  # vm-gateway masquerades WireGuard client traffic with its VCN IP, so this rule
  # is a belt-and-braces catch for direct WireGuard subnet routing if masquerade
  # is ever reconfigured.
  ingress_security_rules {
    protocol = "all"
    source   = var.wireguard_subnet
  }
}

# --- Subnets ---

resource "oci_core_subnet" "gateway" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.homelab.id
  cidr_block        = var.gateway_subnet_cidr
  display_name      = "gateway-subnet"
  dns_label         = "gateway"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.gateway.id]
}

resource "oci_core_subnet" "telemetry" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.homelab.id
  cidr_block        = var.telemetry_subnet_cidr
  display_name      = "telemetry-subnet"
  dns_label         = "telemetry"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.telemetry.id]
}
