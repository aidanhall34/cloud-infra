#cloud-config
# vm-gateway: WireGuard VPN, Blocky DNS, Nginx static site, otelcol-contrib
# OS: Ubuntu 24.04 Minimal (x86 / VM.Standard.E2.1.Micro)

package_update: true
package_upgrade: true

packages:
  - wireguard
  - wireguard-tools
  - nginx
  - certbot
  - python3-certbot-nginx
  - curl
  - wget
  - unzip
  - iptables
  - iptables-persistent
  - netfilter-persistent

write_files:
  # ── WireGuard private key ────────────────────────────────────────────────
  # Generated once externally (wg genkey), stored as CI secret WG_GATEWAY_PRIVATE_KEY.
  # The public key is derived from this on first boot and written to public.key.
  # Using a pre-defined key means the MikroTik peer config survives instance recreation.
  - path: /etc/wireguard/private.key
    permissions: "0600"
    content: |
      ${wireguard_private_key}

  # ── WireGuard setup script ───────────────────────────────────────────────
  # Derives the public key, builds wg0.conf, brings up the interface.
  - path: /usr/local/bin/wireguard-setup.sh
    permissions: "0700"
    content: |
      #!/bin/bash
      set -e
      umask 077
      chmod 600 /etc/wireguard/private.key
      wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key
      PRIMARY_IF=$(ip route show default | awk '/default/{print $5}' | head -1)
      cat > /etc/wireguard/wg0.conf <<EOF
      [Interface]
      Address = 10.10.0.1/24
      ListenPort = ${wireguard_port}
      PrivateKey = $(cat /etc/wireguard/private.key)
      PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; \
                 iptables -A FORWARD -o wg0 -j ACCEPT; \
                 iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
                 iptables -D FORWARD -o wg0 -j ACCEPT; \
                 iptables -t nat -D POSTROUTING -o $PRIMARY_IF -j MASQUERADE
      %{ if wireguard_mikrotik_public_key != "" ~}

      [Peer]
      # MikroTik router
      PublicKey = ${wireguard_mikrotik_public_key}
      # AllowedIPs covers the MikroTik's VPN IP + the VCN range so the router
      # can reach vm-telemetry (10.0.2.10) through this gateway.
      AllowedIPs = 10.10.0.2/32, 10.0.0.0/16
      %{ else ~}

      # MikroTik peer not yet configured.
      # After provisioning, add it manually:
      #   sudo wg set wg0 peer <mikrotik-pubkey> allowed-ips 10.10.0.2/32,10.0.0.0/16
      #   sudo wg-quick save wg0
      # Then store the key as CI secret WG_MIKROTIK_PUBLIC_KEY and re-apply Terraform.
      %{ endif ~}
      EOF
      chmod 600 /etc/wireguard/wg0.conf

  # ── Blocky: provisioned config files ────────────────────────────────────
  # These raw files are read by blocky-generate-config.sh at provisioning
  # time to produce /etc/blocky/config.yaml.  Edit them in config/dns/ and
  # re-apply Terraform to pick up changes on the next instance.

  - path: /etc/blocky/adlists.txt
    content: |
      ${indent(6, blocky_adlists)}

  - path: /etc/blocky/allowlist.txt
    content: |
      ${indent(6, blocky_allowlist)}

  - path: /etc/blocky/local_dns.txt
    content: |
      ${indent(6, blocky_local_dns)}

  # ── Blocky: config generator ─────────────────────────────────────────────
  # Reads the three provisioned files and writes /etc/blocky/config.yaml.
  # Run on first boot and whenever the provisioned files change.
  - path: /usr/local/bin/blocky-generate-config.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -e

      ADLISTS=/etc/blocky/adlists.txt
      ALLOWLIST=/etc/blocky/allowlist.txt
      LOCAL_DNS=/etc/blocky/local_dns.txt
      OUTPUT=/etc/blocky/config.yaml

      # Build denylist URL entries (strip comments and blank lines)
      adlist_yaml=""
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
        adlist_yaml+="      - \"${line}\"\n"
      done < "$ADLISTS"

      # Build allowlist inline block (strip comments and blank lines)
      allow_yaml=""
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
        allow_yaml+="        ${line}\n"
      done < "$ALLOWLIST"

      # Build custom DNS mapping (format: ip  hostname → hostname: ip)
      dns_yaml=""
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
        ip=$(awk '{print $1}' <<< "$line")
        host=$(awk '{print $2}' <<< "$line")
        [[ -z "$ip" || -z "$host" ]] && continue
        dns_yaml+="    ${host}: ${ip}\n"
      done < "$LOCAL_DNS"

      {
        cat <<'HEADER'
      upstream:
        groups:
          default:
            - 1.1.1.1
            - 1.0.0.1

      blocking:
        denylists:
          ads:
      HEADER

        if [ -n "$adlist_yaml" ]; then
          printf '%b' "$adlist_yaml"
        else
          echo "      # no adlists configured"
        fi

        cat <<'ALLOW_HEADER'
        allowlists:
          ads:
            - |
      ALLOW_HEADER

        if [ -n "$allow_yaml" ]; then
          printf '%b' "$allow_yaml"
        else
          echo "        # empty"
        fi

        cat <<'GROUPS'
        clientGroupsBlock:
          default:
            - ads

      customDNS:
        customTTL: 1h
        filterUnmappedTypes: false
        mapping:
      GROUPS

        if [ -n "$dns_yaml" ]; then
          printf '%b' "$dns_yaml"
        else
          echo "    # no local DNS entries"
        fi

        cat <<'FOOTER'

      ports:
        dns: "0.0.0.0:53"
        http: "0.0.0.0:4000"

      prometheus:
        enable: true
        path: /metrics

      log:
        level: info
        format: json
      FOOTER

      } > "$OUTPUT"

      echo "blocky-generate-config: wrote $OUTPUT"

  # ── Blocky systemd unit ──────────────────────────────────────────────────
  - path: /etc/systemd/system/blocky.service
    content: |
      [Unit]
      Description=Blocky DNS ad-blocker
      After=network.target

      [Service]
      Type=simple
      User=blocky
      # CAP_NET_BIND_SERVICE allows binding port 53 without root
      AmbientCapabilities=CAP_NET_BIND_SERVICE
      CapabilityBoundingSet=CAP_NET_BIND_SERVICE
      ExecStart=/usr/local/bin/blocky --config /etc/blocky/config.yaml
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

  # ── Nginx: public static site ────────────────────────────────────────────
  - path: /etc/nginx/sites-available/homelab
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          server_name ${static_site_domain != "" ? static_site_domain : "_"};
          root /var/www/homelab;
          index index.html;

          location / {
              try_files $uri $uri/ =404;
          }
      }

  - path: /var/www/homelab/index.html
    content: |
      <!DOCTYPE html>
      <html lang="en">
      <head><meta charset="UTF-8"><title>Home</title></head>
      <body><p>Hello.</p></body>
      </html>

  # ── otelcol-contrib config ───────────────────────────────────────────────
  - path: /etc/otelcol-contrib/config.yaml
    content: |
      extensions:
        file_storage:
          directory: /var/lib/otelcol-contrib/filestore

      receivers:
        hostmetrics:
          collection_interval: 30s
          scrapers:
            cpu:
            memory:
            disk:
            filesystem:
            network:
            load:
            process:
              mute_process_name_error: true

        journald:
          directory: /var/log/journal
          start_at: end
          priority: info
          storage: file_storage

        # Scrape Blocky's Prometheus metrics endpoint
        prometheus:
          config:
            scrape_configs:
              - job_name: blocky
                scrape_interval: 30s
                static_configs:
                  - targets: ['localhost:4000']

      processors:
        batch:
          timeout: 10s
        resourcedetection:
          detectors: [system]
          system:
            hostname_sources: [os]

      exporters:
        otlphttp/metrics:
          endpoint: http://${telemetry_hostname}:8428/opentelemetry
          tls:
            insecure: true
        # loki exporter was removed in otelcol-contrib v0.131.0.
        # Loki 3.x accepts native OTLP at /otlp — otelcol appends /v1/logs.
        otlphttp/loki:
          endpoint: http://${telemetry_hostname}:3100/otlp
          tls:
            insecure: true
        otlp/traces:
          endpoint: ${telemetry_hostname}:4317
          tls:
            insecure: true

      service:
        extensions: [file_storage]
        pipelines:
          metrics:
            receivers:  [hostmetrics, prometheus]
            processors: [resourcedetection, batch]
            exporters:  [otlphttp/metrics]
          logs:
            receivers:  [journald]
            processors: [resourcedetection, batch]
            exporters:  [otlphttp/loki]
          traces:
            receivers:  []
            processors: [batch]
            exporters:  [otlp/traces]

runcmd:
  # ── Kernel: enable IP forwarding ─────────────────────────────────────────
  - echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  - sysctl -p

  # ── WireGuard ─────────────────────────────────────────────────────────────
  - /usr/local/bin/wireguard-setup.sh
  - systemctl enable wg-quick@wg0
  - systemctl start wg-quick@wg0

  # ── Blocky DNS ────────────────────────────────────────────────────────────
  - useradd --system --no-create-home --shell /usr/sbin/nologin blocky
  - wget -q -O /tmp/blocky.tar.gz "https://github.com/0xERR0R/blocky/releases/download/v${blocky_version}/blocky_v${blocky_version}_Linux_x86_64.tar.gz"
  - tar -xzf /tmp/blocky.tar.gz -C /tmp blocky
  - mv /tmp/blocky /usr/local/bin/blocky
  - chmod +x /usr/local/bin/blocky
  - rm /tmp/blocky.tar.gz
  - mkdir -p /etc/blocky
  - chown -R blocky:blocky /etc/blocky
  - /usr/local/bin/blocky-generate-config.sh
  - systemctl daemon-reload
  - systemctl enable blocky
  - systemctl start blocky

  # ── Nginx ─────────────────────────────────────────────────────────────────
  - rm -f /etc/nginx/sites-enabled/default
  - ln -s /etc/nginx/sites-available/homelab /etc/nginx/sites-enabled/homelab
  - systemctl enable nginx
  - systemctl start nginx
  %{ if static_site_domain != "" ~}
  - certbot --nginx -d ${static_site_domain} --non-interactive --agree-tos -m admin@${static_site_domain} --redirect
  %{ endif ~}

  # ── otelcol-contrib ───────────────────────────────────────────────────────
  - wget -q -O /tmp/otelcol.deb "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${otelcol_version}/otelcol-contrib_${otelcol_version}_linux_amd64.deb"
  - dpkg -i /tmp/otelcol.deb
  - rm /tmp/otelcol.deb
  - mkdir -p /var/lib/otelcol-contrib/filestore
  - usermod -aG systemd-journal otelcol-contrib
  - systemctl enable otelcol-contrib
  - systemctl restart otelcol-contrib
