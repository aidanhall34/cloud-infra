packer {
  required_version = ">= 1.10.0"

  required_plugins {
    linode = {
      version = ">= 1.0.2"
      source  = "github.com/linode/linode"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "linode_token" {
  description = "Linode API token (Images:Read/Write scope required)"
  type        = string
  sensitive   = true
}

variable "linode_region" {
  description = "Linode region to build and store the image in"
  type        = string
  default     = "ap-southeast"
}

variable "instance_type" {
  description = "Linode instance type used for the build VM"
  type        = string
  default     = "g6-nanode-1"
}

variable "alpine_version" {
  description = "Alpine Linux major.minor version — selects the Linode base image (e.g. 3.22)"
  type        = string
  default     = "3.22"
}

variable "git_sha" {
  description = "Short git commit SHA baked into the image label for traceability (e.g. abc1234)"
  type        = string
  default     = "dev"
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  image_label = "alpine-gateway-${var.alpine_version}-${var.git_sha}"
}

# ── Linode builder ────────────────────────────────────────────────────────────
# Creates a temporary Linode instance from Linode's official Alpine image,
# runs provisioners, then snapshots it as a reusable custom image.

source "linode" "alpine_gateway" {
  linode_token      = var.linode_token
  region            = var.linode_region
  instance_type     = var.instance_type
  image             = "linode/alpine${var.alpine_version}"
  image_label       = local.image_label
  image_description = "Alpine gateway image built by Packer"

  ssh_username = "root"
}

# ── Build ─────────────────────────────────────────────────────────────────────

build {
  name    = "alpine-linode-gateway"
  sources = ["source.linode.alpine_gateway"]

  # Install cloud-init + common (otelcol-contrib) + gateway services.
  provisioner "ansible" {
    playbook_file = "${path.root}/../../ansible/gateway.yml"
    user          = "root"
    extra_arguments = [
      "--connection=ssh",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
    ]
  }

  # Final SSH hardening and cloud-init reset before the image is snapshotted.
  provisioner "shell" {
    inline = [
      "sed -i 's|#\\?PasswordAuthentication.*|PasswordAuthentication no|' /etc/ssh/sshd_config",
      "sed -i 's|#\\?PermitRootLogin.*|PermitRootLogin prohibit-password|' /etc/ssh/sshd_config",
      "cloud-init clean --logs",
    ]
  }
}
