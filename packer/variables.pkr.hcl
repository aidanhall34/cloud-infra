variable "alpine_version" {
  description = "Alpine Linux version to build (major.minor.patch)"
  type        = string
  default     = "3.21.3"
}

variable "alpine_arch" {
  description = "Target CPU architecture"
  type        = string
  default     = "x86_64"
}

variable "disk_size" {
  description = "Disk size for the image in MiB"
  type        = number
  default     = 4096
}

variable "memory" {
  description = "RAM for the QEMU build VM in MiB"
  type        = number
  default     = 512
}

variable "cpus" {
  description = "CPUs for the QEMU build VM"
  type        = number
  default     = 2
}

variable "ssh_password" {
  description = "Temporary root password used by Packer during the build — not present in the final image"
  type        = string
  default     = "packer"
  sensitive   = true
}

variable "oci_namespace" {
  description = "OCI Object Storage namespace (tenancy namespace)"
  type        = string
}

variable "oci_bucket" {
  description = "OCI Object Storage bucket to upload the image to"
  type        = string
  default     = "packer-images"
}

variable "oci_compartment_ocid" {
  description = "OCI compartment OCID where the custom image will be registered"
  type        = string
}

variable "oci_region" {
  description = "OCI region"
  type        = string
  default     = "ap-sydney-1"
}
