# Homelab

> FYI - The bulk of this code is AI generated.\
> While I am doing my best to add tests etc, this an unstable project.\
> Nothing should be trusted without vetting.\
> With enough testing I may be able to remove this warning, but for now it is in rapid development, so I
> am marking it as `very unstable`

Infrastructure-as-code for a Linode gateway running WireGuard VPN, Blocky DNS,
Grafana/VictoriaMetrics/Loki/Tempo observability, and a MikroTik router integration.

## Documentation

- [docs/terraform.md](docs/terraform.md) — Terraform layout and module reference
- [docs/cloud-migration-plan.md](docs/cloud-migration-plan.md) — Migration plan
- [docs/cloud-infrastructure.md](docs/cloud-infrastructure.md) — Infrastructure overview

## Required Tools

The following tools must be installed and available on your `PATH` before using the Makefile targets.

| Tool | Purpose | Install |
|------|---------|---------|
| [make](https://www.gnu.org/software/make/) | Run Makefile targets | OS package manager (`apt install make`, `brew install make`) |
| [uv](https://docs.astral.sh/uv/) | Python dependency management (ansible + scripts) | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| [Docker](https://docs.docker.com/get-docker/) | Local dev stack, CI via act, Molecule tests | <https://docs.docker.com/get-docker/> |
| [Terraform](https://developer.hashicorp.com/terraform/install) | Provision Linode infrastructure | <https://developer.hashicorp.com/terraform/install> |
| [GitHub CLI (`gh`)](https://cli.github.com/) | Upload secrets, manage PRs | <https://cli.github.com/> |
| [act](https://github.com/nektos/act) | Run GitHub Actions workflows locally | <https://github.com/nektos/act> |
| [Packer](https://developer.hashicorp.com/packer/install) | Build VM images | <https://developer.hashicorp.com/packer/install> |
| [AWS CLI (`aws`)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Restore dev volumes from S3-compatible storage (`make dev-restore`) | <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html> |
| [GnuPG (`gpg`)](https://gnupg.org/download/) | Decrypt GPG-encrypted volume backups during restore | `apt install gnupg` / `brew install gnupg` |
| [linode-cli](https://github.com/linode/linode-cli) | Create API tokens and manage Linode resources (`make linode-*`) — installed via `make setup` | `pip install linode-cli` or `make setup` |

After installing the tools above, run `make setup` to create the Python virtual environments.

## Available Make Targets

### Terraform — local

| Target | Description | Source |
|---|---|---|
| `make tf-init` | Initialise Terraform — generates a temporary Linode token and OBJ key automatically | [Makefile:128](Makefile#L128) |
| `make tf-init-bucket` | Create the Linode Object Storage bucket for Terraform state (idempotent — skips if bucket already exists) | [Makefile:135](Makefile#L135) |
| `make tf-plan` | Run terraform plan — generates a temporary Linode token and OBJ key automatically | [Makefile:145](Makefile#L145) |
| `make tf-deploy` | Deploy gateway — generates a temporary Linode token and OBJ key automatically | [Makefile:153](Makefile#L153) |
| `make tf-debug-bucket` | Debug: create a temp OBJ key and list the Terraform state bucket with aws s3 ls | [Makefile:162](Makefile#L162) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:187](Makefile#L187) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:192](Makefile#L192) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:197](Makefile#L197) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:202](Makefile#L202) |

### CI — local act runs

| Target | Description | Source |
|---|---|---|
| `make ci-pre-commit` | Run the pre-commit workflow locally via act | [Makefile:211](Makefile#L211) |
| `make ci-unit-tests` | Run the unit-tests workflow locally via act | [Makefile:218](Makefile#L218) |
| `make ci-molecule-gateway` | Run the molecule-gateway workflow locally via act | [Makefile:225](Makefile#L225) |
| `make ci-packer-build` | Run the packer-build workflow locally via act (simulates push to main) | [Makefile:232](Makefile#L232) |
| `make ci-mikrotik` | Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT) | [Makefile:239](Makefile#L239) |
| `make ci-terraform-plan` | Run the terraform-plan workflow locally via act (requires TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE) | [Makefile:252](Makefile#L252) |
| `make ci-terraform-apply` | Manually run terraform-apply via act (simulates workflow_dispatch from main — requires TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE) | [Makefile:261](Makefile#L261) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make generate-wireguard-keys` | Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg) | [Makefile:272](Makefile#L272) |
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:295](Makefile#L295) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:300](Makefile#L300) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:305](Makefile#L305) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) and git hooks | [Makefile:319](Makefile#L319) |
| `make install-hooks` | Write .git/hooks/pre-commit and make it executable | [Makefile:325](Makefile#L325) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make pre-commit` | Run all linters and unit tests (invoked by the git pre-commit hook) | [Makefile:333](Makefile#L333) |
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:336](Makefile#L336) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:339](Makefile#L339) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:347](Makefile#L347) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:352](Makefile#L352) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:359](Makefile#L359) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:364](Makefile#L364) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:369](Makefile#L369) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:374](Makefile#L374) |

### Linode — credentials

| Target | Description | Source |
|---|---|---|
| `make linode-login` | Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli) | [Makefile:390](Makefile#L390) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:396](Makefile#L396) |
| `make packer-build-gateway` | Build the Alpine gateway image — generates a temporary Linode token automatically | [Makefile:401](Makefile#L401) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:409](Makefile#L409) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:415](Makefile#L415) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-volumes` | Create persistent telemetry volumes (idempotent — safe to run on an existing setup) | [Makefile:422](Makefile#L422) |
| `make dev-secrets` | Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:428](Makefile#L428) |
| `make dev-backup-secrets` | Generate secrets/dev-backup.env with a random GPG passphrase and S3 credential placeholders | [Makefile:442](Makefile#L442) |
| `make dev-backup` | Trigger an ad-hoc backup of all dev volumes to S3 (Prometheus TSDB snapshot taken first via exec-pre hook) | [Makefile:473](Makefile#L473) |
| `make dev-restore` | Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup. | [Makefile:477](Makefile#L477) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:481](Makefile#L481) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:492](Makefile#L492) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:500](Makefile#L500) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:510](Makefile#L510) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:515](Makefile#L515) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:520](Makefile#L520) |

### Scripts container

| Target | Description | Source |
|---|---|---|
| `make build` | Build the scripts container image (aidanhall34/homelab:latest) | [Makefile:528](Makefile#L528) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:538](Makefile#L538) |

