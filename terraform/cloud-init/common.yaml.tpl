#cloud-config
# Shared configuration applied to all VMs.
# Merged before the VM-specific template; VM-specific runcmd appends after these.

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - unzip

runcmd:
  # ── otelcol-contrib ───────────────────────────────────────────────────────
  # dpkg --print-architecture returns 'amd64' on x86 and 'arm64' on ARM,
  # matching the release asset naming convention.
  - |
    set -e
    ARCH=$(dpkg --print-architecture)
    wget -q -O /tmp/otelcol.deb "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${otelcol_version}/otelcol-contrib_${otelcol_version}_linux_$ARCH.deb"
    dpkg --force-confdef -i /tmp/otelcol.deb
    rm /tmp/otelcol.deb
    mkdir -p /var/lib/otelcol-contrib/filestore
    usermod -aG systemd-journal otelcol-contrib
    systemctl enable otelcol-contrib
    systemctl restart otelcol-contrib
