variable "linode_token" {
  description = "Linode API token — use TF_VAR_linode_token or terraform.tfvars (never commit)"
  type        = string
  sensitive   = true
}

variable "linode_region" {
  description = "Linode region to deploy into"
  type        = string
  default     = "ap-southeast"
}

variable "instance_type" {
  description = "Linode instance type for the gateway"
  type        = string
  default     = "g6-nanode-1"
}

variable "ssh_public_key" {
  description = "SSH public key for root access to the gateway"
  type        = string
}

variable "allowed_ip_range" {
  description = "The only CIDR block permitted to send inbound traffic to the gateway (e.g. your home IP: 203.0.113.1/32). All other inbound traffic is dropped."
  type        = string
}
