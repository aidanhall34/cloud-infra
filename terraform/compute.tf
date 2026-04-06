resource "linode_instance" "gateway" {
  label  = "gateway"
  region = var.linode_region
  type   = var.instance_type
  image  = var.gateway_image

  authorized_keys = [var.ssh_public_key]

  tags = ["gateway"]

  lifecycle {
    create_before_destroy = true
  }
}
