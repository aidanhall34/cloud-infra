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

# act: use the medium-sized runner image and pass the GitHub token.
# Override GITHUB_TOKEN in the environment before running CI targets.
ACT_FLAGS   := --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
               --secret GITHUB_TOKEN="$(GITHUB_TOKEN)"

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
	{ cd $(TF_DIR) && terraform plan -out=/tmp/tfplan.binary; } $(L)

.PHONY: tf-apply
tf-apply: ## Apply the last plan produced by `make plan`
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform apply /tmp/tfplan.binary; } $(L)

.PHONY: tf-destroy
tf-destroy: ## Destroy all managed infrastructure (prompts for confirmation)
	@mkdir -p $(LOG_DIR)
	{ cd $(TF_DIR) && terraform destroy; } $(L)

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

## CI via act (local GitHub Actions runner)

.PHONY: ci-plan
ci-plan: ## Run the deploy workflow (plan action) locally via act
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --input action=plan \
	  --workflows .github/workflows/deploy.yml; } $(L)

.PHONY: ci-apply
ci-apply: ## Run the deploy workflow (apply action) locally via act
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --input action=apply \
	  --workflows .github/workflows/deploy.yml; } $(L)

.PHONY: ci-destroy
ci-destroy: ## Run the deploy workflow (destroy action) locally via act
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --input action=destroy \
	  --workflows .github/workflows/deploy.yml; } $(L)

## Secrets and credentials

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

## MikroTik router automation

.PHONY: mikrotik
mikrotik: ## Configure MikroTik WireGuard + DNS via act (local only, not real GitHub Actions)
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --workflows .github/workflows/mikrotik-configure.yml; } $(L)

## Cloud-init boot tests
# Renders each VM's cloud-init template with test values and runs it on a real
# Ubuntu VM (via GitHub Actions or act) to verify all services actually boot.
# ubuntu-24.04-arm is used for telemetry (ARM64); ubuntu-latest for gateway (x86_64).

# act ARM64 platform mapping.
# catthehacker/ubuntu:act-latest is a multi-arch image; Docker pulls the arm64
# variant automatically. On x86 hosts, install qemu-user-static for emulation:
#   sudo apt-get install -y qemu-user-static
ACT_ARM_FLAGS := --platform ubuntu-24.04-arm=catthehacker/ubuntu:act-latest \
                 --container-architecture linux/arm64 \
                 --secret GITHUB_TOKEN="$(GITHUB_TOKEN)"

.PHONY: test-telemetry
test-telemetry: ## Boot-test the telemetry VM cloud-init (Grafana, VictoriaMetrics, Loki, Tempo)
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_ARM_FLAGS) \
	  --job test-telemetry \
	  --workflows .github/workflows/test-cloud-init.yml; } $(L)

.PHONY: test-gateway
test-gateway: ## Boot-test the gateway VM cloud-init (Blocky DNS, Nginx)
	@mkdir -p $(LOG_DIR)
	{ act workflow_dispatch --json $(ACT_FLAGS) \
	  --job test-gateway \
	  --workflows .github/workflows/test-cloud-init.yml; } $(L)

.PHONY: test
test: test-gateway test-telemetry ## Run all cloud-init boot tests

.PHONY: test-clean
test-clean: ## Remove all test containers left over from a local test run
	@mkdir -p $(LOG_DIR)
	{ docker rm -f testenv minio 2>/dev/null || true; } $(L)

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

## Packer — image builds

.PHONY: packer-init
packer-init: ## Initialise Packer plugins for all builds (run once after checkout)
	@mkdir -p $(LOG_DIR)
	{ cd packer/alpine && packer init .; } $(L)
	{ cd packer/gateway && packer init .; } $(L)

.PHONY: packer-build
packer-build: ## Build the Alpine base image and upload it to OCI
	@mkdir -p $(LOG_DIR)
	{ cd packer/alpine && packer build -var-file=vars.pkrvars.hcl .; } $(L)

.PHONY: packer-build-gateway
packer-build-gateway: ## Build the Alpine gateway image (WireGuard, Blocky, Nginx) and upload it to OCI
	@mkdir -p $(LOG_DIR)
	{ cd packer/gateway && packer build -var-file=vars.pkrvars.hcl .; } $(L)

.PHONY: packer-validate
packer-validate: ## Validate all Packer configurations without building
	@mkdir -p $(LOG_DIR)
	{ cd packer/alpine && packer validate -var-file=vars.pkrvars.hcl .; } $(L)
	{ cd packer/gateway && packer validate -var-file=vars.pkrvars.hcl .; } $(L)

.PHONY: packer-fmt
packer-fmt: ## Format Packer configuration (all builds)
	@mkdir -p $(LOG_DIR)
	{ cd packer && packer fmt -recursive .; } $(L)

## Development

.PHONY: dev-secrets
dev-secrets: ## Generate dev Grafana admin credentials (secrets/dev-grafana.env) — skips if already present
	@mkdir -p $(SECRETS_DIR)
	{ if [ -f $(SECRETS_DIR)/dev-grafana.env ]; then \
	    echo "$(SECRETS_DIR)/dev-grafana.env already exists — delete it to regenerate."; \
	  else \
	    password=$$(openssl rand -hex 16); \
	    printf 'GF_SECURITY_ADMIN_PASSWORD=%s\nGRAFANA_URL=http://admin:%s@lgtm:3000\n' \
	        "$$password" "$$password" > $(SECRETS_DIR)/dev-grafana.env; \
	    chmod 600 $(SECRETS_DIR)/dev-grafana.env; \
	    echo "Generated $(SECRETS_DIR)/dev-grafana.env"; \
	  fi; } $(L)

.PHONY: otelcol-validate
otelcol-validate: ## Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm)
	@mkdir -p $(LOG_DIR)
	{ docker run --rm \
		-v "$(CURDIR)/$(DEV_DIR)/otelcol-extra.yaml:/etc/otelcol/extra.yaml:ro" \
		--entrypoint="" \
		grafana/otel-lgtm:$(LGTM_VERSION) \
		/otel-lgtm/otelcol-contrib/otelcol-contrib validate \
			--feature-gates service.profilesSupport \
			--config=file:/otel-lgtm/otelcol-config.yaml \
			--config=file:/etc/otelcol/extra.yaml; } $(L)

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
dev-up: ## Start the local LGTM development stack (Grafana on :3000, anonymous admin)
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

