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
  # Alpine minor version derived from full version string e.g. "3.21.3" → "3.21"
  alpine_minor = join(".", slice(split(".", var.alpine_version), 0, 2))

  iso_url      = "https://dl-cdn.alpinelinux.org/alpine/v${local.alpine_minor}/releases/${var.alpine_arch}/alpine-virt-${var.alpine_version}-${var.alpine_arch}.iso"
  iso_checksum = "file:${local.iso_url}.sha512"

  image_name = "alpine-base-${var.alpine_version}-${var.alpine_arch}"
  image_file = "${path.root}/output/${local.image_name}/${local.image_name}.qcow2"
}

# ── QEMU builder ─────────────────────────────────────────────────────────────
# Boots the Alpine virt ISO, runs an unattended install using http/alpine-answers,
# configures SSH in the installed system via chroot, reboots, then Ansible runs.

source "qemu" "alpine" {
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

  # SSH communicator — connects after the installed system reboots.
  communicator           = "ssh"
  ssh_username           = "root"
  ssh_password           = var.ssh_password
  ssh_timeout            = "15m"
  ssh_handshake_attempts = 50

  # Serve the answer file via Packer's built-in HTTP server.
  http_directory = "${path.root}/http"

  # ── Boot sequence ──────────────────────────────────────────────────────────
  # 1. Login to Alpine live environment (no password in virt ISO)
  # 2. Bring up networking via DHCP
  # 3. Fetch the answer file from Packer's HTTP server and run unattended install
  # 4. After install: chroot into the new root, enable SSH root login + set password
  # 5. Reboot — Packer SSH reconnects to the installed system
  boot_wait = "30s"
  boot_command = [
    "root<enter><wait5>",
    "ifconfig eth0 up && udhcpc -i eth0<enter><wait10>",
    "wget -q http://{{ .HTTPIP }}:{{ .HTTPPort }}/alpine-answers -O /tmp/answers<enter><wait3>",
    "setup-alpine -f /tmp/answers<enter><wait5>y<enter><wait120>",
    # Locate the installed root ext4 partition and configure SSH access for Packer
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
  name    = "alpine-oci-base"
  sources = ["source.qemu.alpine"]

  # Run Ansible to install and configure cloud-init (latest) and harden the base image.
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    user          = "root"
    extra_arguments = [
      "--connection=ssh",
      "-e", "ansible_python_interpreter=/usr/bin/python3",
    ]
  }

  # Lock down SSH after provisioning: disable root password login (cloud-init
  # will inject authorised keys on first boot from OCI instance metadata).
  provisioner "shell" {
    inline = [
      "sed -i 's|PasswordAuthentication yes|PasswordAuthentication no|' /etc/ssh/sshd_config",
      "sed -i 's|PermitRootLogin yes|PermitRootLogin prohibit-password|' /etc/ssh/sshd_config",
      "cloud-init clean --logs",
    ]
  }

  # Upload the QCOW2 to OCI Object Storage and register it as a custom image.
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
