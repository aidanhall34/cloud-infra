resource "linode_instance" "gateway" {
  label  = "gateway"
  region = var.linode_region
  type   = var.instance_type
  image  = data.linode_images.gateway.images[0].id

  authorized_keys = [var.ssh_public_key]

  tags = ["gateway"]

  lifecycle {
    create_before_destroy = true
  }
}
