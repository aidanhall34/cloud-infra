# Telemetry S3 storage — OCI Object Storage buckets (S3-compatible)
#
# These buckets are provisioned before vm-telemetry boots so that Loki, Tempo,
# and VictoriaMetrics (vmbackup) have writable destinations on first boot.
# The telemetry instance has explicit depends_on for all three (see compute.tf).
#
# prevent_destroy guards against accidental loss of observability data.
# To delete a bucket you must first remove the prevent_destroy lifecycle rule.

data "oci_objectstorage_namespace" "telemetry" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "loki" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.telemetry.namespace
  name           = var.telemetry_s3_bucket_loki
  access_type    = "NoPublicAccess"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_bucket" "tempo" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.telemetry.namespace
  name           = var.telemetry_s3_bucket_tempo
  access_type    = "NoPublicAccess"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_bucket" "vmbackup" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.telemetry.namespace
  name           = var.telemetry_s3_bucket_vmbackup
  access_type    = "NoPublicAccess"

  lifecycle {
    prevent_destroy = true
  }
}
