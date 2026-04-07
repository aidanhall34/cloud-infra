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
| `make tf-init` | Initialise Terraform — generates a temporary Linode token and OBJ key automatically | [Makefile:115](Makefile#L115) |
| `make tf-init-bucket` | Create the Linode Object Storage bucket for Terraform state (idempotent — skips if bucket already exists) | [Makefile:122](Makefile#L122) |
| `make tf-plan` | Run terraform plan — generates a temporary Linode token and OBJ key automatically | [Makefile:132](Makefile#L132) |
| `make tf-deploy` | Deploy gateway — generates a temporary Linode token and OBJ key automatically | [Makefile:140](Makefile#L140) |
| `make tf-debug-bucket` | Debug: create a temp OBJ key and list the Terraform state bucket with aws s3 ls - DO NOT LOG | [Makefile:149](Makefile#L149) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:174](Makefile#L174) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:179](Makefile#L179) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:184](Makefile#L184) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:189](Makefile#L189) |

### CI — local act runs

| Target | Description | Source |
|---|---|---|
| `make ci-pre-commit` | Run the pre-commit workflow locally via act | [Makefile:197](Makefile#L197) |
| `make ci-unit-tests` | Run the unit-tests workflow locally via act | [Makefile:203](Makefile#L203) |
| `make ci-molecule` | Run the molecule workflow locally via act | [Makefile:209](Makefile#L209) |
| `make ci-mikrotik` | Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT) | [Makefile:215](Makefile#L215) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make generate-wireguard-keys` | Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg) | [Makefile:229](Makefile#L229) |
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:252](Makefile#L252) |
| `make configure-branch-protection` | Configure main branch protection rules via GitHub CLI (idempotent) | [Makefile:257](Makefile#L257) |
| `make configure-github-app` | Upload GitHub App credentials (APP_ID, APP_PRIVATE_KEY) to cloud-infra and homelab-deploy | [Makefile:265](Makefile#L265) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:277](Makefile#L277) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:282](Makefile#L282) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) and git hooks | [Makefile:296](Makefile#L296) |
| `make install-hooks` | Write .git/hooks/pre-commit and make it executable | [Makefile:302](Makefile#L302) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make pre-commit` | Run all linters and unit tests (invoked by the git pre-commit hook) | [Makefile:310](Makefile#L310) |
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:313](Makefile#L313) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:316](Makefile#L316) |
| `make mypy-scripts` | Type-check scripts/ with mypy — files discovered via scripts/pyproject.toml | [Makefile:322](Makefile#L322) |
| `make mypy-ansible` | Type-check ansible/library and ansible/tests with mypy — files discovered via ansible/pyproject.toml | [Makefile:327](Makefile#L327) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:334](Makefile#L334) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:339](Makefile#L339) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:346](Makefile#L346) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:351](Makefile#L351) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:356](Makefile#L356) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:361](Makefile#L361) |

### Linode — credentials

| Target | Description | Source |
|---|---|---|
| `make linode-login` | Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli) | [Makefile:377](Makefile#L377) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:383](Makefile#L383) |
| `make packer-build-gateway` | Build the Alpine gateway image — generates a temporary Linode token automatically | [Makefile:388](Makefile#L388) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:396](Makefile#L396) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:402](Makefile#L402) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-volumes` | Create persistent telemetry volumes (idempotent — safe to run on an existing setup) | [Makefile:409](Makefile#L409) |
| `make dev-secrets` | Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:415](Makefile#L415) |
| `make dev-backup-secrets` | Generate secrets/dev-backup.env with a random GPG passphrase and S3 credential placeholders | [Makefile:429](Makefile#L429) |
| `make dev-backup` | Trigger an ad-hoc backup of all dev volumes to S3 (Prometheus TSDB snapshot taken first via exec-pre hook) | [Makefile:460](Makefile#L460) |
| `make dev-restore` | Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup. | [Makefile:464](Makefile#L464) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:468](Makefile#L468) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:479](Makefile#L479) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:487](Makefile#L487) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:497](Makefile#L497) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:502](Makefile#L502) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:507](Makefile#L507) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:515](Makefile#L515) |

