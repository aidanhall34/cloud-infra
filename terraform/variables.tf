# --- Oracle Cloud credentials ---

variable "tenancy_ocid" {
  description = "OCID of the tenancy. Found under Profile → Tenancy."
  type        = string
}

variable "user_ocid" {
  description = "OCID of the API user. Found under Profile → User Settings."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API key. Shown after uploading public key in User Settings → API Keys."
  type        = string
}

variable "private_key_path" {
  description = "Local path to the OCI API private key (.pem)."
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI region identifier."
  type        = string
  default     = "ap-sydney-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment to deploy into. Use tenancy_ocid for the root compartment."
  type        = string
}

# --- Instance access ---

variable "ssh_public_key" {
  description = "SSH public key for instance access (contents of ~/.ssh/id_ed25519.pub or similar)."
  type        = string
}

# --- Network ---

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "gateway_subnet_cidr" {
  description = "CIDR for the gateway VM subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "telemetry_subnet_cidr" {
  description = "CIDR for the telemetry VM subnet."
  type        = string
  default     = "10.0.2.0/24"
}

# Private IPs are assigned dynamically by OCI DHCP.
# Inter-VM communication uses OCI VCN internal DNS, which is stable across
# instance replacements and allows create_before_destroy to work correctly.

variable "wireguard_subnet" {
  description = "WireGuard VPN overlay subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "wireguard_port" {
  description = "WireGuard listen port."
  type        = number
  default     = 51820
}

# --- Availability domain ---

variable "availability_domain_index" {
  description = "Index of the availability domain to use (0-based). Try 1 or 2 if Always Free capacity is unavailable."
  type        = number
  default     = 0
}

# --- Image overrides ---
# Leave empty to auto-select latest Ubuntu 24.04 Minimal from the marketplace.
# Set to a specific OCID if the data source lookup fails or you want to pin a version.

variable "gateway_image_ocid" {
  description = "OCID of the custom Alpine gateway image built with packer/gateway.pkr.hcl. Required — run `make packer-build-gateway` to build and upload."
  type        = string
}

variable "telemetry_image_ocid" {
  description = "Image OCID override for vm-telemetry. Leave empty for auto-selection."
  type        = string
  default     = ""
}

# --- Application ---

variable "static_site_domain" {
  description = "Domain name for the public static site (e.g. example.com). Used for Nginx server_name and certbot. Set to empty string to skip TLS provisioning."
  type        = string
  default     = ""
}

# Secrets are read from the secrets/ directory in secrets.tf — not variables.
# For CI/CD, write secret files before running terraform:
#   echo "$SECRET" > ../secrets/<filename>

# --- Grafana ---

variable "grafana_oauth_auth_url" {
  description = "Grafana GitHub OAuth authorize URL. Override in tests to point at a local mock server."
  type        = string
  default     = "https://github.com/login/oauth/authorize"
}

variable "grafana_oauth_token_url" {
  description = "Grafana GitHub OAuth token exchange URL."
  type        = string
  default     = "https://github.com/login/oauth/access_token"
}

variable "grafana_oauth_api_url" {
  description = "Grafana GitHub OAuth user-info API URL."
  type        = string
  default     = "https://api.github.com/user"
}

variable "grafana_github_org" {
  description = "GitHub organisation (or personal username) whose members may sign in to Grafana."
  type        = string
  default     = ""
}

variable "grafana_admin_user" {
  description = "GitHub username that is granted the Grafana Admin role via role_attribute_path."
  type        = string
  default     = ""
}

# --- Component versions ---
# Update these when new releases are available.


variable "victoriametrics_version" {
  description = "VictoriaMetrics version. https://github.com/VictoriaMetrics/VictoriaMetrics/releases"
  type        = string
  default     = "1.138.0"
}

variable "loki_version" {
  description = "Loki version. https://github.com/grafana/loki/releases"
  type        = string
  default     = "3.7.1"
}

variable "tempo_version" {
  description = "Tempo version. https://github.com/grafana/tempo/releases"
  type        = string
  default     = "2.10.3"
}

# --- Telemetry S3 storage ---
# OCI Object Storage S3-compatible endpoint format:
#   https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
# Credentials are read from secrets/ (see secrets.tf).
# Buckets are provisioned by Terraform (see storage.tf) before the VM boots.

variable "telemetry_s3_endpoint" {
  description = "S3-compatible endpoint URL for telemetry storage. OCI format: https://<namespace>.compat.objectstorage.<region>.oraclecloud.com"
  type        = string
  default     = ""
}

variable "telemetry_s3_region" {
  description = "S3 region identifier for telemetry storage buckets."
  type        = string
  default     = "ap-sydney-1"
}

variable "telemetry_s3_bucket_loki" {
  description = "S3 bucket name for Loki chunk storage."
  type        = string
  default     = "loki-chunks"
}

variable "telemetry_s3_bucket_tempo" {
  description = "S3 bucket name for Tempo trace storage."
  type        = string
  default     = "tempo-traces"
}

variable "telemetry_s3_bucket_vmbackup" {
  description = "S3 bucket name for VictoriaMetrics backups (vmbackup/vmrestore)."
  type        = string
  default     = "victoriametrics-backup"
}
