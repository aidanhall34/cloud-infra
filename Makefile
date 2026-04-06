# Homelab infrastructure Makefile
#
# All Terraform operations default to the terraform/ directory.
# Secrets are read from secrets/ (gitignored). Run `make upload-secrets` to
# push them to GitHub Actions.
#
# Prerequisites:
#   - Terraform >= 1.6
#   - GitHub CLI (gh) authenticated
#   - act (https://github.com/nektos/act) for local CI runs
#   - secrets/ directory populated (see make setup-oauth, make generate-grafana-key)
#
# Usage: make <target>

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

TF_DIR      := terraform
SECRETS_DIR := secrets
SCRIPTS_DIR := scripts
ANSIBLE_DIR := ansible
DEV_DIR     := dev

# grafana/otel-lgtm image version — otelcol and prometheus are bundled inside it.
# Run `make otelcol-validate` and `make prometheus-validate` after upgrading.
LGTM_VERSION       := 0.23.0
export LGTM_VERSION
OTELCOL_VERSION    := 0.147.0   # bundled in grafana/otel-lgtm:$(LGTM_VERSION)
PROMETHEUS_VERSION := 3.10.0    # bundled in grafana/otel-lgtm:$(LGTM_VERSION)
BLOCKY_VERSION     := 0.29.0

# act: use the medium-sized runner image and inject the GitHub token via gh CLI.
# GITHUB_TOKEN defaults to `gh auth token` — override in the environment if needed.
# DISCORD_WEBHOOK_URL is read from secrets/discord_webhook_url — override in the environment if needed.
GITHUB_TOKEN         ?= $(shell gh auth token)
DISCORD_WEBHOOK_URL  ?= $(shell cat $(SECRETS_DIR)/discord_webhook_url 2>/dev/null)
ACT_FLAGS            := --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
                        --secret GITHUB_TOKEN="$(GITHUB_TOKEN)" \
                        --secret DISCORD_WEBHOOK_URL="$(DISCORD_WEBHOOK_URL)"

# ── Logging ───────────────────────────────────────────────────────────────────
# Each recipe tees its combined stdout+stderr to dev/logs/<target>.log (append).
# The terminal output is unchanged — tee writes to both the log and stdout.
# $@ expands to the current target name inside each recipe.

LOG_DIR := dev/logs
LOGFILE  = $(LOG_DIR)/$@.log
L        = 2>&1 | tee -a $(LOGFILE)

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN { FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\n" } \
	     /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	     /^##/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 4) } \
	     END { printf "\n" }' $(MAKEFILE_LIST)

## Terraform — local

.PHONY: tf-init
tf-init: ## Initialise Terraform with the local secrets/backend.hcl
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform init -backend-config=../$(SECRETS_DIR)/backend.hcl; } $(L)

.PHONY: tf-plan
tf-plan: ## Run terraform plan (writes plan to /tmp/tfplan.binary)
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && OTEL_TRACES_EXPORTER=otlp terraform plan -out=/tmp/tfplan.binary; } $(L)

.PHONY: tf-apply
tf-apply: ## Apply the last plan produced by `make plan`
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && OTEL_TRACES_EXPORTER=otlp terraform apply /tmp/tfplan.binary; } $(L)

.PHONY: tf-destroy
tf-destroy: ## Destroy all managed infrastructure (prompts for confirmation)
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && OTEL_TRACES_EXPORTER=otlp terraform destroy; } $(L)

.PHONY: tf-fmt
tf-fmt: ## Run terraform fmt recursively
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform fmt -recursive; } $(L)

.PHONY: tf-lint
tf-lint: ## Check Terraform formatting without modifying files (no provider init required)
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform fmt -check -recursive; } $(L)

.PHONY: tf-validate
tf-validate: ## Run terraform validate (requires terraform init first)
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform validate; } $(L)

## CI — local act runs
# GITHUB_TOKEN is injected automatically via `gh auth token`.
# Other secret env vars (LINODE_TOKEN etc.) must be set before running these targets.

.PHONY: ci-pre-commit
ci-pre-commit: ## Run the pre-commit workflow locally via act
	@mkdir -p $(LOG_DIR)
	{ act push --json $(ACT_FLAGS) \
	  --workflows .github/workflows/pre-commit.yml; } $(L)

.PHONY: ci-unit-tests
ci-unit-tests: ## Run the unit-tests workflow locally via act
	@mkdir -p $(LOG_DIR)
	{ act push --json $(ACT_FLAGS) \
	  --workflows .github/workflows/unit-tests.yml; } $(L)

.PHONY: ci-molecule-gateway
ci-molecule-gateway: ## Run the molecule-gateway workflow locally via act
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --workflows .github/workflows/molecule-gateway.yml; } $(L)

.PHONY: ci-packer-build
ci-packer-build: ## Run the packer-build workflow locally via act (requires LINODE_TOKEN)
	@mkdir -p $(LOG_DIR)
	{ act push --json $(ACT_FLAGS) \
	  --secret LINODE_TOKEN="$(LINODE_TOKEN)" \
	  --workflows .github/workflows/packer-build.yml; } $(L)

.PHONY: ci-mikrotik
ci-mikrotik: ## Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT)
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --secret MIKROTIK_HOST="$(MIKROTIK_HOST)" \
	  --secret MIKROTIK_USERNAME="$(MIKROTIK_USERNAME)" \
	  --secret MIKROTIK_PASSWORD="$(MIKROTIK_PASSWORD)" \
	  --secret MIKROTIK_WG_PRIVATE_KEY="$$(cat $(SECRETS_DIR)/wireguard_mikrotik_private.key)" \
	  --secret MIKROTIK_WG_GATEWAY_PUBLIC_KEY="$$(cat $(SECRETS_DIR)/wireguard_gateway_public.key)" \
	  --secret MIKROTIK_WG_GATEWAY_ENDPOINT="$(MIKROTIK_WG_GATEWAY_ENDPOINT)" \
	  --workflows .github/workflows/mikrotik.yml; } $(L)

.PHONY: ci-terraform-apply
ci-terraform-apply: ## Manually run terraform-apply via act (requires LINODE_TOKEN, TF_STATE_*, TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE, GATEWAY_IMAGE)
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --input gateway_image="$(GATEWAY_IMAGE)" \
	  --secret LINODE_TOKEN="$(LINODE_TOKEN)" \
	  --secret TF_STATE_BUCKET="$(TF_STATE_BUCKET)" \
	  --secret TF_STATE_REGION="$(TF_STATE_REGION)" \
	  --secret TF_STATE_ENDPOINT="$(TF_STATE_ENDPOINT)" \
	  --secret TF_STATE_ACCESS_KEY="$(TF_STATE_ACCESS_KEY)" \
	  --secret TF_STATE_SECRET_KEY="$(TF_STATE_SECRET_KEY)" \
	  --secret TF_SSH_PUBLIC_KEY="$(TF_SSH_PUBLIC_KEY)" \
	  --secret TF_ALLOWED_IP_RANGE="$(TF_ALLOWED_IP_RANGE)" \
	  --workflows .github/workflows/terraform-apply.yml; } $(L)

## Secrets and credentials

.PHONY: generate-wireguard-keys
generate-wireguard-keys: ## Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg)
	@mkdir -p $(SECRETS_DIR)
	{ changed=0; \
	  if [ ! -f $(SECRETS_DIR)/wireguard_gateway_private.key ]; then \
	    wg genkey | tee $(SECRETS_DIR)/wireguard_gateway_private.key | wg pubkey > $(SECRETS_DIR)/wireguard_gateway_public.key; \
	    chmod 600 $(SECRETS_DIR)/wireguard_gateway_private.key; \
	    echo "Generated: $(SECRETS_DIR)/wireguard_gateway_private.key"; \
	    echo "Generated: $(SECRETS_DIR)/wireguard_gateway_public.key"; \
	    changed=1; \
	  fi; \
	  if [ ! -f $(SECRETS_DIR)/wireguard_mikrotik_private.key ]; then \
	    wg genkey | tee $(SECRETS_DIR)/wireguard_mikrotik_private.key | wg pubkey > $(SECRETS_DIR)/wireguard_mikrotik_public.key; \
	    chmod 600 $(SECRETS_DIR)/wireguard_mikrotik_private.key; \
	    echo "Generated: $(SECRETS_DIR)/wireguard_mikrotik_private.key"; \
	    echo "Generated: $(SECRETS_DIR)/wireguard_mikrotik_public.key"; \
	    changed=1; \
	  fi; \
	  [ "$$changed" = "0" ] && echo "All WireGuard keys already exist — delete them first to regenerate."; \
	  echo ""; \
	  echo "Gateway public key:  $$(cat $(SECRETS_DIR)/wireguard_gateway_public.key)"; \
	  echo "MikroTik public key: $$(cat $(SECRETS_DIR)/wireguard_mikrotik_public.key)"; }

.PHONY: upload-secrets
upload-secrets: ## Upload all secrets from secrets/ to GitHub Actions
	@mkdir -p $(LOG_DIR)
	{ $(SCRIPTS_DIR)/upload-secrets.sh; } $(L)

.PHONY: setup-oauth
setup-oauth: ## Create the GitHub OAuth App for Grafana SSO (writes to secrets/)
	@mkdir -p $(LOG_DIR)
	{ $(SCRIPTS_DIR)/setup-github-oauth.sh; } $(L)

.PHONY: generate-grafana-key
generate-grafana-key: ## Generate a new Grafana session signing key (secrets/grafana_secret_key)
	@mkdir -p $(LOG_DIR)
	{ if [ -f $(SECRETS_DIR)/grafana_secret_key ]; then \
	    echo "secrets/grafana_secret_key already exists. Delete it first if you want to regenerate."; \
	    exit 1; \
	  fi; \
	  openssl rand -hex 32 > $(SECRETS_DIR)/grafana_secret_key; \
	  chmod 600 $(SECRETS_DIR)/grafana_secret_key; \
	  echo "Generated: $(SECRETS_DIR)/grafana_secret_key"; \
	  echo "Run 'make upload-secrets' to push the new key to GitHub."; } $(L)

## Setup

.PHONY: setup
setup: ## Install all Python dependencies (ansible/ and scripts/ virtual environments)
	@mkdir -p $(LOG_DIR)
	{ cd $(ANSIBLE_DIR) && uv sync; } $(L)
	{ cd $(SCRIPTS_DIR) && uv sync; } $(L)

## Linting

.PHONY: lint
lint: lint-python ansible-lint tf-lint packer-validate otelcol-validate prometheus-validate blocky-validate ## Run all linters and validators (tf-validate excluded: requires terraform init)

.PHONY: lint-python
lint-python: ## Lint all Python code with ruff (scripts/ and ansible/)
	@mkdir -p $(LOG_DIR)
	{ cd $(SCRIPTS_DIR) && uv run ruff check .; } $(L)
	{ cd $(ANSIBLE_DIR) && uv run ruff check .; } $(L)

## Ansible

.PHONY: ansible-lint
ansible-lint: ## Lint Ansible roles and modules with ansible-lint
	@mkdir -p $(LOG_DIR)
	{ cd $(ANSIBLE_DIR) && uv run ansible-lint -f json; } $(L)

.PHONY: ansible-molecule
ansible-molecule: ## Run molecule integration tests for all roles (Docker, systemd-compatible containers)
	@mkdir -p $(LOG_DIR)
	{ for role in $(ANSIBLE_DIR)/roles/*/; do \
		(cd "$$role" && uv run molecule test); \
	done; } $(L)

.PHONY: ansible-molecule-gateway
ansible-molecule-gateway: ## Run molecule integration tests for the gateway role
	@mkdir -p $(LOG_DIR)
	{ cd "$(ANSIBLE_DIR)/roles/gateway" && uv run molecule test; } $(L)

.PHONY: ansible-molecule-common
ansible-molecule-common: ## Run molecule integration tests for the common role
	@mkdir -p $(LOG_DIR)
	{ cd "$(ANSIBLE_DIR)/roles/common" && uv run molecule test; } $(L)

.PHONY: ansible-pytest
ansible-pytest: ## Run pytest unit tests for custom Ansible modules
	@mkdir -p $(LOG_DIR)
	{ cd $(ANSIBLE_DIR) && uv run pytest tests/unit/ -v; } $(L)

.PHONY: ansible-doc
ansible-doc: ## Generate documentation for all custom Ansible modules into docs/ansible-modules/
	@mkdir -p $(LOG_DIR)
	@mkdir -p docs/ansible-modules
	{ for role_lib in $(ANSIBLE_DIR)/roles/*/library; do \
		for module in "$$role_lib"/*.py; do \
			[ -f "$$module" ] || continue; \
			name=$$(basename "$$module" .py); \
			rel=$$(realpath --relative-to=$(ANSIBLE_DIR) "$$role_lib"); \
			cd $(ANSIBLE_DIR) && uv run ansible-doc -M "$$rel" "$$name" > "../docs/ansible-modules/$$name.txt"; \
			cd ..; \
		done; \
	done; } $(L)

## Linode — credentials

.PHONY: linode-login
linode-login: ## Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli)
	cd $(SCRIPTS_DIR) && uv run linode-cli configure

.PHONY: linode-packer-token
linode-packer-token: ## Create a Linode packer API token expiring in 24 hours (linodes + images read/write, event read_only) - DO NOT LOG
	@mkdir -p $(LOG_DIR)
	EXPIRY=$$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%S'); \
	cd $(SCRIPTS_DIR) && uv run linode-cli profile token-create \
	    --label "packer-$$(date -u '+%Y%m%d')" \
	    --expiry "$$EXPIRY" \
	    --scopes "linodes:read_write images:read_write events:read_only" \
	    --json --pretty;

.PHONY: linode-deploy-token
linode-deploy-token: ## Create a Linode API token for Terraform deployments (linodes + firewall read/write) - DO NOT LOG
	@mkdir -p $(LOG_DIR)
	EXPIRY=$$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%S'); \
	cd $(SCRIPTS_DIR) && uv run linode-cli profile token-create \
	    --label "terraform-$$(date -u '+%Y%m%d')" \
	    --expiry "$$EXPIRY" \
	    --scopes "linodes:read_write firewall:read_write events:read_only" \
	    --json --pretty;

## Packer — image builds

.PHONY: packer-init
packer-init: ## Initialise Packer plugins for all builds (run once after checkout)
	@mkdir -p $(LOG_DIR)
	{ cd packer/gateway && packer init .; } $(L)

.PHONY: packer-build-gateway
packer-build-gateway: ## Build the Alpine gateway image (WireGuard, Blocky, Nginx) and upload it to Linode
	@mkdir -p $(LOG_DIR)
	{ flag=$$([ -f packer/gateway/vars.pkrvars.hcl ] && echo "-var-file=vars.pkrvars.hcl"); \
	  cd packer/gateway && packer build $$flag .; } $(L)

.PHONY: packer-validate
packer-validate: packer-init ## Validate all Packer configurations without building
	@mkdir -p $(LOG_DIR)
	{ flag=$$([ -f packer/gateway/vars.pkrvars.hcl ] && echo "-var-file=vars.pkrvars.hcl"); \
	  cd packer/gateway && packer validate $$flag .; } $(L)

.PHONY: packer-fmt
packer-fmt: ## Format Packer configuration (all builds)
	@mkdir -p $(LOG_DIR)
	{ cd packer && packer fmt -recursive .; } $(L)

## Development

.PHONY: dev-volumes
dev-volumes: ## Create persistent telemetry volumes (idempotent — safe to run on an existing setup)
	docker volume create dev-prometheus-data
	docker volume create dev-loki-data
	docker volume create dev-tempo-data

.PHONY: dev-secrets
dev-secrets: ## Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present
	@mkdir -p $(SECRETS_DIR)
	{ if [ -f $(SECRETS_DIR)/dev-grafana.env ]; then \
	    echo "$(SECRETS_DIR)/dev-grafana.env already exists — delete it to regenerate."; \
	  else \
	    password=$$(openssl rand -hex 16); \
	    renderer_token=$$(openssl rand -hex 24); \
	    printf 'GF_SECURITY_ADMIN_PASSWORD=%s\nGRAFANA_URL=http://lgtm:3000\nAUTH_TOKEN=%s\nGF_RENDERING_RENDERER_TOKEN=%s\n' \
	        "$$password" "$$renderer_token" "$$renderer_token" > $(SECRETS_DIR)/dev-grafana.env; \
	    chmod 600 $(SECRETS_DIR)/dev-grafana.env; \
	    echo "Generated $(SECRETS_DIR)/dev-grafana.env"; \
	  fi; } $(L)

.PHONY: dev-backup-secrets
dev-backup-secrets: ## Generate secrets/dev-backup.env with a random GPG passphrase and S3 credential placeholders
	@mkdir -p $(SECRETS_DIR)
	{ if [ -f $(SECRETS_DIR)/dev-backup.env ]; then \
	    echo "$(SECRETS_DIR)/dev-backup.env already exists — delete it to regenerate."; \
	  else \
	    passphrase=$$(openssl rand -hex 32); \
	    { printf '# S3-compatible object storage credentials for offen/docker-volume-backup.\n'; \
	      printf '# Supports AWS S3, Cloudflare R2, Backblaze B2, MinIO, etc.\n'; \
	      printf '# Fill in the S3 values below, then run: make dev-up\n'; \
	      printf '#\n'; \
	      printf '# AWS_ENDPOINT is optional — omit for AWS S3, set for S3-compatible providers:\n'; \
	      printf '#   Cloudflare R2: https://<account>.r2.cloudflarestorage.com\n'; \
	      printf '#   Backblaze B2:  https://s3.<region>.backblazeb2.com\n'; \
	      printf 'AWS_S3_BUCKET_NAME=\n'; \
	      printf 'AWS_S3_PATH=homelab/dev\n'; \
	      printf 'AWS_ACCESS_KEY_ID=\n'; \
	      printf 'AWS_SECRET_ACCESS_KEY=\n'; \
	      printf 'AWS_REGION=auto\n'; \
	      printf '# AWS_ENDPOINT=\n'; \
	      printf '#\n'; \
	      printf '# GPG passphrase — generated by make dev-backup-secrets, do not edit.\n'; \
	      printf '# Backups are encrypted with this key before upload. Keep it safe:\n'; \
	      printf '# losing it makes existing backups unrecoverable.\n'; \
	      printf 'GPG_PASSPHRASE=%s\n' "$$passphrase"; \
	    } > $(SECRETS_DIR)/dev-backup.env; \
	    chmod 600 $(SECRETS_DIR)/dev-backup.env; \
	    echo "Generated $(SECRETS_DIR)/dev-backup.env"; \
	    echo "  GPG passphrase written — fill in S3 credentials before running make dev-up"; \
	  fi; }

.PHONY: dev-backup
dev-backup: ## Trigger an ad-hoc backup of all dev volumes to S3 (Prometheus TSDB snapshot taken first via exec-pre hook)
	docker exec dev-backup backup

.PHONY: dev-restore
dev-restore: ## Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup.
	@$(DEV_DIR)/restore-volumes.sh $(if $(FILE),$(FILE),)

.PHONY: otelcol-validate
otelcol-validate: ## Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm)
	@mkdir -p $(LOG_DIR)
	{ docker run --rm \
		-v "$(CURDIR)/$(DEV_DIR)/otelcol-config.yaml:/otel-lgtm/otelcol-config.yaml:ro" \
		--entrypoint="" \
		grafana/otel-lgtm:$(LGTM_VERSION) \
		/otel-lgtm/otelcol-contrib/otelcol-contrib validate \
			--feature-gates service.profilesSupport \
			--config=file:/otel-lgtm/otelcol-config.yaml ; } $(L)

.PHONY: blocky-validate
blocky-validate: ## Validate blocky config with blocky v$(BLOCKY_VERSION)
	@mkdir -p $(LOG_DIR)
	{ docker run --rm \
		-v "$(CURDIR)/$(ANSIBLE_DIR)/roles/gateway/files/blocky-default.yaml:/etc/blocky/config.yaml:ro" \
		ghcr.io/0xerr0r/blocky:v$(BLOCKY_VERSION) \
		validate -c /etc/blocky/config.yaml; } $(L)

.PHONY: prometheus-validate
prometheus-validate: ## Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm)
	@mkdir -p $(LOG_DIR)
	{ docker run --rm \
		-v "$(CURDIR)/$(DEV_DIR)/prometheus.yaml:/etc/prometheus/prometheus.yaml:ro" \
		--entrypoint="" \
		grafana/otel-lgtm:$(LGTM_VERSION) \
		/otel-lgtm/prometheus/promtool check config \
			/etc/prometheus/prometheus.yaml; } $(L)

.PHONY: dev-up
dev-up: dev-volumes ## Start the local LGTM development stack (Grafana on :3000, anonymous admin)
	@mkdir -p $(LOG_DIR)
	{ docker compose -f $(DEV_DIR)/docker-compose.yml up -d --wait ; } $(L)

.PHONY: dev-down
dev-down: ## Stop and remove the local LGTM development stack
	@mkdir -p $(LOG_DIR)
	{ docker compose -f $(DEV_DIR)/docker-compose.yml down; } $(L)

.PHONY: dev-logs
dev-logs: ## Tail logs from all development stack services
	docker compose -f $(DEV_DIR)/docker-compose.yml logs -f

## Scripts container

.PHONY: build
build: ## Build the scripts container image (aidanhall34/homelab:latest)
	@mkdir -p $(LOG_DIR)
	{ docker build \
		--progress rawjson \
		-t aidanhall34/homelab:latest \
		$(SCRIPTS_DIR); } $(L)

## Documentation

.PHONY: readme
readme: ## Regenerate README.md from README.md.tpl and Makefile comments
	@mkdir -p $(LOG_DIR)
	{ uv run --python 3.13 $(SCRIPTS_DIR)/generate-readme.py; } $(L)

