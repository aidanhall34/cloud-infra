#!/usr/bin/env bash
# Upload a built QCOW2 image to OCI Object Storage and register it as a custom image.
# Called by the Packer shell-local post-processor.
# Required environment variables (injected by Packer via post-processor env):
#   IMAGE_FILE   — path to the built QCOW2 file
#   IMAGE_NAME   — display name / object key (without .qcow2)
#   OCI_NAMESPACE, OCI_BUCKET, OCI_COMPARTMENT_OCID, OCI_REGION

set -euo pipefail

: "${IMAGE_FILE:?IMAGE_FILE must be set}"
: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${OCI_NAMESPACE:?OCI_NAMESPACE must be set}"
: "${OCI_BUCKET:?OCI_BUCKET must be set}"
: "${OCI_COMPARTMENT_OCID:?OCI_COMPARTMENT_OCID must be set}"
: "${OCI_REGION:?OCI_REGION must be set}"

OBJECT_KEY="${IMAGE_NAME}.qcow2"

echo "==> Uploading ${IMAGE_FILE} to oci://${OCI_BUCKET}/${OBJECT_KEY} ..."
oci os object put \
  --namespace "${OCI_NAMESPACE}" \
  --bucket-name "${OCI_BUCKET}" \
  --file "${IMAGE_FILE}" \
  --name "${OBJECT_KEY}" \
  --region "${OCI_REGION}" \
  --force

echo "==> Registering ${OBJECT_KEY} as an OCI custom image ..."
IMAGE_OCID=$(oci compute image import from-object \
  --compartment-id "${OCI_COMPARTMENT_OCID}" \
  --namespace-name "${OCI_NAMESPACE}" \
  --bucket-name "${OCI_BUCKET}" \
  --name "${OBJECT_KEY}" \
  --display-name "${IMAGE_NAME}" \
  --source-image-type QCOW2 \
  --launch-mode PARAVIRTUALIZED \
  --operating-system "Custom Linux" \
  --operating-system-version "Alpine Linux" \
  --region "${OCI_REGION}" \
  --query 'data.id' \
  --raw-output)

echo "==> Waiting for image import to complete ..."
oci compute image get \
  --image-id "${IMAGE_OCID}" \
  --region "${OCI_REGION}" \
  --wait-for-state AVAILABLE \
  --max-wait-seconds 1800

echo "==> Image available: ${IMAGE_OCID}"
