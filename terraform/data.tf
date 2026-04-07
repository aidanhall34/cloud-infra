# Automatically resolves the latest private gateway image produced by `make packer-build-gateway`.
# Images are labelled `alpine-gateway-<alpine_version>-<git_sha>` — the newest one is selected.
data "linode_images" "gateway" {
  latest = true

  filter {
    name     = "label"
    values   = ["alpine-gateway-"]
    match_by = "substring"
  }

  filter {
    name   = "is_public"
    values = ["false"]
  }
}
