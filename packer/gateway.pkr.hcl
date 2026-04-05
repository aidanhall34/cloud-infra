packer {
  required_version = ">= 1.10.0"

  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  alpine_minor = join(".", slice(split(".", var.alpine_version), 0, 2))

  iso_url      = "https://dl-cdn.alpinelinux.org/alpine/v${local.alpine_minor}/releases/${var.alpine_arch}/alpine-virt-${var.alpine_version}-${var.alpine_arch}.iso"
  iso_checksum = "file:${local.iso_url}.sha512"

  image_name = "alpine-gateway-${var.alpine_version}-${var.alpine_arch}"
  image_file = "${path.root}/output/${local.image_name}/${local.image_name}.qcow2"
}

# ── QEMU builder ─────────────────────────────────────────────────────────────
# Identical boot sequence to the base image — unattended Alpine install via
# http/alpine-answers, then Ansible provisions gateway services.

source "qemu" "alpine_gateway" {
  iso_url          = local.iso_url
  iso_checksum     = local.iso_checksum
  output_directory = "${path.root}/output/${local.image_name}"
  vm_name          = "${local.image_name}.qcow2"

  disk_size      = "${var.disk_size}M"
  memory         = var.memory
  cpus           = var.cpus
  format         = "qcow2"
  accelerator    = "kvm"
  net_device     = "virtio-net"
  disk_interface = "virtio"

  communicator           = "ssh"
  ssh_username           = "root"
  ssh_password           = var.ssh_password
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 50

  http_directory = "${path.root}/http"

  boot_wait = "30s"
  boot_command = [
    "root<enter><wait5>",
    "ifconfig eth0 up && udhcpc -i eth0<enter><wait10>",
    "wget -q http://{{ .HTTPIP }}:{{ .HTTPPort }}/alpine-answers -O /tmp/answers<enter><wait3>",
    "setup-alpine -f /tmp/answers<enter><wait5>y<enter><wait120>",
    "ROOT=$(blkid -t TYPE=ext4 -o device | grep vda | tail -1)<enter><wait2>",
    "mount $ROOT /mnt<enter><wait2>",
    "echo 'root:${var.ssh_password}' | chroot /mnt chpasswd<enter><wait2>",
    "sed -i 's|#\\?PermitRootLogin.*|PermitRootLogin yes|' /mnt/etc/ssh/sshd_config<enter>",
    "sed -i 's|#\\?PasswordAuthentication.*|PasswordAuthentication yes|' /mnt/etc/ssh/sshd_config<enter>",
    "umount /mnt<enter><wait2>",
    "reboot<enter>",
  ]

  shutdown_command = "poweroff"
}

# ── Build ─────────────────────────────────────────────────────────────────────

build {
  name    = "alpine-oci-gateway"
  sources = ["source.qemu.alpine_gateway"]

  # Run Ansible: base cloud-init setup + common (otelcol-contrib) + gateway services.
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/gateway.yml"
    user          = "root"
    extra_arguments = [
      "--connection=ssh",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
    ]
  }

  # Lock down SSH after provisioning.
  provisioner "shell" {
    inline = [
      "sed -i 's|PasswordAuthentication yes|PasswordAuthentication no|' /etc/ssh/sshd_config",
      "sed -i 's|PermitRootLogin yes|PermitRootLogin prohibit-password|' /etc/ssh/sshd_config",
      "cloud-init clean --logs",
    ]
  }

  # Upload to OCI Object Storage and register as a custom image.
  post-processor "shell-local" {
    environment_vars = [
      "IMAGE_FILE=${local.image_file}",
      "IMAGE_NAME=${local.image_name}",
      "OCI_NAMESPACE=${var.oci_namespace}",
      "OCI_BUCKET=${var.oci_bucket}",
      "OCI_COMPARTMENT_OCID=${var.oci_compartment_ocid}",
      "OCI_REGION=${var.oci_region}",
    ]
    script = "${path.root}/scripts/upload-to-oci.sh"
  }
}
