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

# act: use the medium-sized runner image and pass the GitHub token.
# Override GITHUB_TOKEN in the environment before running CI targets.
ACT_FLAGS   := --platform ubuntu-latest=catthehacker/ubuntu:act-latest \
               --secret GITHUB_TOKEN="$(GITHUB_TOKEN)"

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN { FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\n" } \
	     /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	     /^##/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 4) } \
	     END { printf "\n" }' $(MAKEFILE_LIST)

## Terraform — local

.PHONY: init
init: ## Initialise Terraform with the local secrets/backend.hcl
	cd $(TF_DIR) && terraform init -backend-config=../$(SECRETS_DIR)/backend.hcl

.PHONY: plan
plan: ## Run terraform plan (writes plan to /tmp/tfplan.binary)
	cd $(TF_DIR) && terraform plan -out=/tmp/tfplan.binary

.PHONY: apply
apply: ## Apply the last plan produced by `make plan`
	cd $(TF_DIR) && terraform apply /tmp/tfplan.binary

.PHONY: destroy
destroy: ## Destroy all managed infrastructure (prompts for confirmation)
	cd $(TF_DIR) && terraform destroy

.PHONY: fmt
fmt: ## Run terraform fmt recursively
	cd $(TF_DIR) && terraform fmt -recursive

.PHONY: validate
validate: ## Run terraform validate
	cd $(TF_DIR) && terraform validate

## CI via act (local GitHub Actions runner)

.PHONY: ci-plan
ci-plan: ## Run the deploy workflow (plan action) locally via act
	act workflow_dispatch  --json $(ACT_FLAGS) \
	  --input action=plan \
	  --workflows .github/workflows/deploy.yml

.PHONY: ci-apply
ci-apply: ## Run the deploy workflow (apply action) locally via act
	act workflow_dispatch  --json $(ACT_FLAGS) \
	  --input action=apply \
	  --workflows .github/workflows/deploy.yml

.PHONY: ci-destroy
ci-destroy: ## Run the deploy workflow (destroy action) locally via act
	act workflow_dispatch  --json $(ACT_FLAGS) \
	  --input action=destroy \
	  --workflows .github/workflows/deploy.yml

## Secrets and credentials

.PHONY: upload-secrets
upload-secrets: ## Upload all secrets from secrets/ to GitHub Actions
	$(SCRIPTS_DIR)/upload-secrets.sh

.PHONY: setup-oauth
setup-oauth: ## Create the GitHub OAuth App for Grafana SSO (writes to secrets/)
	$(SCRIPTS_DIR)/setup-github-oauth.sh

.PHONY: generate-grafana-key
generate-grafana-key: ## Generate a new Grafana session signing key (secrets/grafana_secret_key)
	@if [ -f $(SECRETS_DIR)/grafana_secret_key ]; then \
	  echo "secrets/grafana_secret_key already exists. Delete it first if you want to regenerate."; \
	  exit 1; \
	fi
	openssl rand -hex 32 > $(SECRETS_DIR)/grafana_secret_key
	chmod 600 $(SECRETS_DIR)/grafana_secret_key
	@echo "Generated: $(SECRETS_DIR)/grafana_secret_key"
	@echo "Run 'make upload-secrets' to push the new key to GitHub."

## MikroTik router automation

.PHONY: mikrotik
mikrotik: ## Configure MikroTik WireGuard + DNS via act (local only, not real GitHub Actions)
	act workflow_dispatch  --json $(ACT_FLAGS) \
	  --workflows .github/workflows/mikrotik-configure.yml

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
	act workflow_dispatch  --json $(ACT_ARM_FLAGS) \
	  --job test-telemetry \
	  --workflows .github/workflows/test-cloud-init.yml

.PHONY: test-gateway
test-gateway: ## Boot-test the gateway VM cloud-init (Blocky DNS, Nginx)
	act workflow_dispatch  --json $(ACT_FLAGS) \
	  --job test-gateway \
	  --workflows .github/workflows/test-cloud-init.yml

.PHONY: test
test: test-gateway test-telemetry ## Run all cloud-init boot tests

.PHONY: test-clean
test-clean: ## Remove all test containers left over from a local test run
	docker rm -f testenv minio 2>/dev/null || true

## Python linting

.PHONY: lint
lint: ## Lint all Python code with ruff
	cd $(SCRIPTS_DIR) && uv run ruff check .
	cd $(ANSIBLE_DIR) && uv run ruff check .

## Ansible

ANSIBLE_DIR := ansible

.PHONY: ansible-lint
ansible-lint: ## Lint Ansible roles and modules with ansible-lint
	cd $(ANSIBLE_DIR) && uv run ansible-lint -f json

.PHONY: ansible-molecule
ansible-molecule: ## Run molecule integration tests for all roles (Docker, systemd-compatible containers)
	for role in $(ANSIBLE_DIR)/roles/*/; do \
		(cd "$$role" && uv run molecule test); \
	done

.PHONY: ansible-pytest
ansible-pytest: ## Run pytest unit tests for custom Ansible modules
	cd $(ANSIBLE_DIR) && uv run pytest tests/unit/ -v

.PHONY: ansible-doc
ansible-doc: ## Generate documentation for all custom Ansible modules into docs/ansible-modules/
	mkdir -p docs/ansible-modules
	for role_lib in $(ANSIBLE_DIR)/roles/*/library; do \
		for module in "$$role_lib"/*.py; do \
			[ -f "$$module" ] || continue; \
			name=$$(basename "$$module" .py); \
			rel=$$(realpath --relative-to=$(ANSIBLE_DIR) "$$role_lib"); \
			cd $(ANSIBLE_DIR) && uv run ansible-doc -M "$$rel" "$$name" > "../docs/ansible-modules/$$name.txt"; \
			cd ..; \
		done; \
	done

## Packer — image builds

.PHONY: packer-init
packer-init: ## Initialise Packer plugins (run once after checkout)
	cd packer && packer init .

.PHONY: packer-build
packer-build: ## Build the Alpine base image and upload it to OCI
	cd packer && packer build -var-file=alpine.pkrvars.hcl .

.PHONY: packer-validate
packer-validate: ## Validate Packer configuration without building
	cd packer && packer validate -var-file=alpine.pkrvars.hcl .

.PHONY: packer-fmt
packer-fmt: ## Format Packer configuration
	cd packer && packer fmt .

## Scripts container

.PHONY: build
build: ## Build the scripts container image (aidanhall34/homelab:latest)
	docker build \
		--progress rawjson \
		-t aidanhall34/homelab:latest \
		$(SCRIPTS_DIR)

## Documentation

.PHONY: readme
readme: ## Regenerate README.md from README.md.tpl and Makefile comments
	uv run --python 3.13 $(SCRIPTS_DIR)/generate-readme.py
