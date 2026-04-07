terraform {
  required_version = ">= 1.6"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }

  # Credentials are passed via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars.
  backend "s3" {
    bucket = "homelab-tf"
    key    = "homelab.tfstate"
    region = "au-mel"
    endpoints = {
      s3 = "https://au-mel-1.linodeobjects.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "linode" {
  token = var.linode_token
}
