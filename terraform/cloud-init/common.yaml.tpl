#cloud-config
# Shared configuration applied to all VMs.
# Packages and otelcol-contrib are installed by the Packer base/common Ansible roles.
# This file is kept as the common MIME part for merge ordering; VM-specific
# runcmd appends after these.

package_update: false
package_upgrade: false
