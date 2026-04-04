terraform {
  required_version = ">= 1.6"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.0"
    }
  }

  # OCI Object Storage is S3-compatible.
  # All config is supplied at init time via: terraform init -backend-config=../secrets/backend.hcl
  # See terraform/backend.hcl.example for required values and OCI setup instructions.
  #
  # One-time bootstrap: the bucket must exist before the first terraform init.
  # The GitHub Actions workflow creates it automatically (idempotent).
  # For local first-run: see scripts/bootstrap-state-bucket.sh
  backend "s3" {}
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
