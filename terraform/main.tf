terraform {
  required_version = ">= 1.6"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }

  # Backend config is supplied at init time:
  #   terraform init -backend-config=../secrets/backend.hcl
  # See terraform/backend.hcl.example for the required values.
  backend "s3" {}
}

provider "linode" {
  token = var.linode_token
}
