#cloud-config
# vm-telemetry: VictoriaMetrics, Loki, Tempo, Grafana, otelcol-contrib
# OS: Ubuntu 24.04 Minimal (ARM64 / VM.Standard.A1.Flex, 4 OCPU / 24 GB)
# All LGTM services run as native binaries under dedicated system users.
# Merged with common.yaml.tpl which provides: package_update/upgrade, curl/wget/unzip, otelcol-contrib.

packages:
  - gnupg2
  - apt-transport-https
  - software-properties-common
  - ca-certificates

write_files:
  # ── VictoriaMetrics S3 restore script ───────────────────────────────────
  # Runs as ExecStartPre before VictoriaMetrics starts.
  # Restores from S3 on first boot (empty storage dir); skips if data exists.
  # Uses `-` prefix in ExecStartPre so a missing backup does not block startup.
  - path: /usr/local/bin/vmrestore-on-startup.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      STORAGE=/var/lib/victoriametrics
      if [ -d "$STORAGE/data" ] || [ -d "$STORAGE/indexdb" ]; then
          echo "vmrestore: storage has data, skipping restore"
          exit 0
      fi
      echo "vmrestore: storage is empty, attempting restore from S3..."
      export AWS_ACCESS_KEY_ID="${telemetry_s3_access_key}"
      export AWS_SECRET_ACCESS_KEY="${telemetry_s3_secret_key}"
      /usr/local/bin/vmrestore-prod \
          -src="s3://${telemetry_s3_bucket_vmbackup}/victoriametrics" \
          -storageDataPath="$STORAGE" \
          -s3Endpoint="${telemetry_s3_endpoint}" \
          -s3ForcePathStyle=true || {
          echo "vmrestore: no backup found or restore failed, starting fresh"
          exit 0
      }
      echo "vmrestore: restore complete"

  # ── VictoriaMetrics systemd unit ────────────────────────────────────────
  - path: /etc/systemd/system/victoriametrics.service
    content: |
      [Unit]
      Description=VictoriaMetrics
      After=network.target

      [Service]
      Type=simple
      User=victoriametrics
      ExecStartPre=-/usr/local/bin/vmrestore-on-startup.sh
      ExecStart=/usr/local/bin/victoria-metrics \
          -storageDataPath=/var/lib/victoriametrics \
          -retentionPeriod=12 \
          -httpListenAddr=0.0.0.0:8428 \
          -enableTCP6 \
          -loggerFormat=json
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

  # ── VictoriaMetrics backup service + timer ──────────────────────────────
  - path: /etc/systemd/system/victoriametrics-backup.service
    content: |
      [Unit]
      Description=VictoriaMetrics S3 backup (vmbackup)
      After=victoriametrics.service

      [Service]
      Type=oneshot
      User=victoriametrics
      Environment="AWS_ACCESS_KEY_ID=${telemetry_s3_access_key}"
      Environment="AWS_SECRET_ACCESS_KEY=${telemetry_s3_secret_key}"
      ExecStart=/usr/local/bin/vmbackup-prod \
          -storageDataPath=/var/lib/victoriametrics \
          -dst=s3://${telemetry_s3_bucket_vmbackup}/victoriametrics \
          -s3Endpoint=${telemetry_s3_endpoint} \
          -s3ForcePathStyle=true

  - path: /etc/systemd/system/victoriametrics-backup.timer
    content: |
      [Unit]
      Description=Hourly VictoriaMetrics S3 backup

      [Timer]
      OnCalendar=hourly
      Persistent=true

      [Install]
      WantedBy=timers.target

  # ── Loki config ─────────────────────────────────────────────────────────
  - path: /etc/loki/config.yaml
    content: |
      auth_enabled: false

      server:
        http_listen_port: 3100
        grpc_listen_port: 9096
        log_format: json

      common:
        path_prefix: /var/lib/loki
        replication_factor: 1
        ring:
          instance_addr: 127.0.0.1
          kvstore:
            store: inmemory

      storage_config:
        aws:
          bucketnames: ${telemetry_s3_bucket_loki}
          endpoint: ${telemetry_s3_endpoint_host}
          region: ${telemetry_s3_region}
          access_key_id: ${telemetry_s3_access_key}
          secret_access_key: ${telemetry_s3_secret_key}
          s3forcepathstyle: true
          insecure: ${telemetry_s3_insecure}

      ingester:
        chunk_idle_period: 2m
        max_chunk_age: 30m

      schema_config:
        configs:
          - from: 2024-01-01
            store: tsdb
            object_store: s3
            schema: v13
            index:
              prefix: index_
              period: 24h

      limits_config:
        retention_period: 2160h  # 90 days

      compactor:
        working_directory: /var/lib/loki/compactor
        retention_enabled: true
        delete_request_store: s3

  # ── Loki systemd unit ───────────────────────────────────────────────────
  - path: /etc/systemd/system/loki.service
    content: |
      [Unit]
      Description=Loki
      After=network.target

      [Service]
      Type=simple
      User=loki
      ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yaml
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

  # ── Tempo config ────────────────────────────────────────────────────────
  - path: /etc/tempo/config.yaml
    content: |
      server:
        http_listen_port: 3200
        log_format: json

      distributor:
        receivers:
          otlp:
            protocols:
              grpc:
                endpoint: 0.0.0.0:4317
              http:
                endpoint: 0.0.0.0:4318

      ingester:
        trace_idle_period: 10s
        max_block_bytes: 1_000_000
        max_block_duration: 5m

      compactor:
        compaction:
          compaction_window: 1h
          max_block_bytes: 100_000_000
          block_retention: 720h  # 30 days

      storage:
        trace:
          backend: s3
          s3:
            bucket: ${telemetry_s3_bucket_tempo}
            endpoint: ${telemetry_s3_endpoint_host}
            access_key: ${telemetry_s3_access_key}
            secret_key: ${telemetry_s3_secret_key}
            insecure: ${telemetry_s3_insecure}
            forcepathstyle: true
          wal:
            path: /var/lib/tempo/wal

  # ── Tempo systemd unit ──────────────────────────────────────────────────
  - path: /etc/systemd/system/tempo.service
    content: |
      [Unit]
      Description=Tempo
      After=network.target

      [Service]
      Type=simple
      User=tempo
      ExecStart=/usr/local/bin/tempo -config.file=/etc/tempo/config.yaml
      Restart=on-failure
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

  # ── Grafana main config ──────────────────────────────────────────────────
  # Written before grafana-server starts so GitHub OAuth is active on first boot.
  # disable_initial_admin_creation prevents the default admin/admin account.
  # disable_login_form forces GitHub SSO — users cannot log in with a password.
  - path: /etc/grafana/grafana.ini
    content: |
      [server]
      root_url = http://%(domain)s:3000

      [security]
      secret_key = ${grafana_secret_key}
      disable_initial_admin_creation = true

      [log]
      mode = console
      format = json

      [users]
      allow_sign_up = false

      [auth]
      disable_login_form = true

      [auth.github]
      enabled = true
      client_id = ${grafana_github_client_id}
      client_secret = ${grafana_github_client_secret}
      scopes = user:email,read:org
      auth_url = ${grafana_oauth_auth_url}
      token_url = ${grafana_oauth_token_url}
      api_url = ${grafana_oauth_api_url}
      allow_sign_up = true
      %{~ if grafana_github_org != "" }
      allowed_organizations = ${grafana_github_org}
      role_attribute_path = contains(groups[*], '${grafana_github_org}:owners') && 'Admin' || contains(login, '${grafana_admin_user}') && 'Admin' || 'Viewer'
      %{~ endif }

  # ── Grafana datasource provisioning ─────────────────────────────────────
  - path: /etc/grafana/provisioning/datasources/homelab.yaml
    content: |
      apiVersion: 1
      datasources:
        - name: VictoriaMetrics
          type: prometheus
          url: http://localhost:8428
          isDefault: true
          editable: true

        - name: Loki
          type: loki
          url: http://localhost:3100
          editable: true

        - name: Tempo
          type: tempo
          url: http://localhost:3200
          editable: true
          jsonData:
            tracesToLogsV2:
              datasourceUid: loki
            lokiSearch:
              datasourceUid: loki

  # ── otelcol-contrib config ──────────────────────────────────────────────
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

      processors:
        batch:
          timeout: 10s
        resourcedetection:
          detectors: [system]
          system:
            hostname_sources: [os]

      exporters:
        otlphttp/metrics:
          endpoint: http://localhost:8428/opentelemetry
          tls:
            insecure: true
        # loki exporter was removed in otelcol-contrib v0.131.0.
        # Loki 3.x accepts native OTLP at /otlp — otelcol appends /v1/logs.
        otlphttp/loki:
          endpoint: http://localhost:3100/otlp
          tls:
            insecure: true
        otlp/traces:
          endpoint: localhost:4317
          tls:
            insecure: true

      service:
        telemetry:
          logs:
            encoding: json
        extensions: [file_storage]
        pipelines:
          metrics:
            receivers:  [hostmetrics]
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
  # ── Create service users ─────────────────────────────────────────────────
  - useradd --system --no-create-home --shell /usr/sbin/nologin victoriametrics
  - useradd --system --no-create-home --shell /usr/sbin/nologin loki
  - useradd --system --no-create-home --shell /usr/sbin/nologin tempo

  # ── VictoriaMetrics ───────────────────────────────────────────────────────
  - wget -q -O /tmp/vm.tar.gz "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${victoriametrics_version}/victoria-metrics-linux-arm64-v${victoriametrics_version}.tar.gz"
  - tar -xzf /tmp/vm.tar.gz -C /tmp
  - mv /tmp/victoria-metrics-prod /usr/local/bin/victoria-metrics
  - chmod +x /usr/local/bin/victoria-metrics
  - rm /tmp/vm.tar.gz
  # vmbackup / vmrestore (included in vmutils community release)
  - wget -q -O /tmp/vmutils.tar.gz "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${victoriametrics_version}/vmutils-linux-arm64-v${victoriametrics_version}.tar.gz"
  - tar -xzf /tmp/vmutils.tar.gz -C /tmp
  - mv /tmp/vmbackup-prod /usr/local/bin/vmbackup-prod
  - mv /tmp/vmrestore-prod /usr/local/bin/vmrestore-prod
  - chmod +x /usr/local/bin/vmbackup-prod /usr/local/bin/vmrestore-prod
  - rm /tmp/vmutils.tar.gz
  - mkdir -p /var/lib/victoriametrics
  - chown victoriametrics:victoriametrics /var/lib/victoriametrics
  - systemctl daemon-reload
  - systemctl enable victoriametrics
  - systemctl start victoriametrics
  - systemctl enable victoriametrics-backup.timer
  - systemctl start victoriametrics-backup.timer

  # ── Loki ─────────────────────────────────────────────────────────────────
  - wget -q -O /tmp/loki.zip "https://github.com/grafana/loki/releases/download/v${loki_version}/loki-linux-arm64.zip"
  - unzip -q /tmp/loki.zip -d /tmp/loki-extract
  - mv /tmp/loki-extract/loki-linux-arm64 /usr/local/bin/loki
  - chmod +x /usr/local/bin/loki
  - rm -rf /tmp/loki.zip /tmp/loki-extract
  - mkdir -p /var/lib/loki/chunks /var/lib/loki/compactor /etc/loki
  - chown -R loki:loki /var/lib/loki /etc/loki
  - systemctl daemon-reload
  - systemctl enable loki
  - systemctl start loki

  # ── Tempo ─────────────────────────────────────────────────────────────────
  - wget -q -O /tmp/tempo.tar.gz "https://github.com/grafana/tempo/releases/download/v${tempo_version}/tempo_${tempo_version}_linux_arm64.tar.gz"
  - tar -xzf /tmp/tempo.tar.gz -C /tmp
  - mv /tmp/tempo /usr/local/bin/tempo
  - chmod +x /usr/local/bin/tempo
  - rm /tmp/tempo.tar.gz
  - mkdir -p /var/lib/tempo/blocks /var/lib/tempo/wal /etc/tempo
  - chown -R tempo:tempo /var/lib/tempo /etc/tempo
  - systemctl daemon-reload
  - systemctl enable tempo
  - systemctl start tempo

  # ── Grafana (official apt repo, ARM64 native package) ────────────────────
  - wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
  - echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
  - apt-get update -q
  - apt-get install -y grafana
  - mkdir -p /etc/grafana/provisioning/datasources
  # grafana.ini written by write_files above; fix ownership before service start
  - chown grafana:grafana /etc/grafana/grafana.ini
  - systemctl enable grafana-server
  - systemctl start grafana-server

  # otelcol-contrib installed by common.yaml.tpl
