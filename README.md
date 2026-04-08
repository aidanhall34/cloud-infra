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
| `make tf-init` | Initialise Terraform — generates a temporary Linode token and OBJ key automatically | [Makefile:117](Makefile#L117) |
| `make tf-init-bucket` | Create the Linode Object Storage bucket for Terraform state (idempotent — skips if bucket already exists) | [Makefile:124](Makefile#L124) |
| `make tf-plan` | Run terraform plan — generates a temporary Linode token and OBJ key automatically | [Makefile:134](Makefile#L134) |
| `make tf-deploy` | Deploy gateway — generates a temporary Linode token and OBJ key automatically | [Makefile:142](Makefile#L142) |
| `make tf-debug-bucket` | Debug: create a temp OBJ key and list the Terraform state bucket with aws s3 ls - DO NOT LOG | [Makefile:151](Makefile#L151) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:176](Makefile#L176) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:181](Makefile#L181) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:186](Makefile#L186) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:191](Makefile#L191) |

### CI — local act runs

| Target | Description | Source |
|---|---|---|
| `make ci-pre-commit` | Run the pre-commit workflow locally via act | [Makefile:199](Makefile#L199) |
| `make ci-unit-tests` | Run the unit-tests workflow locally via act | [Makefile:205](Makefile#L205) |
| `make ci-molecule` | Run the molecule workflow locally via act | [Makefile:211](Makefile#L211) |
| `make ci-mikrotik` | Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT) | [Makefile:217](Makefile#L217) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make generate-wireguard-keys` | Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg) | [Makefile:231](Makefile#L231) |
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:254](Makefile#L254) |
| `make configure-branch-protection` | Configure main branch protection rules via GitHub CLI (idempotent) | [Makefile:259](Makefile#L259) |
| `make configure-github-app` | Upload GitHub App credentials (APP_ID, APP_PRIVATE_KEY) to cloud-infra and homelab-deploy | [Makefile:267](Makefile#L267) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:279](Makefile#L279) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:284](Makefile#L284) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) and git hooks | [Makefile:298](Makefile#L298) |
| `make install-hooks` | Write .git/hooks/pre-commit and make it executable | [Makefile:304](Makefile#L304) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make pre-commit` | Run all linters and unit tests (invoked by the git pre-commit hook) | [Makefile:312](Makefile#L312) |
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:315](Makefile#L315) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:318](Makefile#L318) |
| `make mypy-scripts` | Type-check scripts/ with mypy — files discovered via scripts/pyproject.toml | [Makefile:324](Makefile#L324) |
| `make mypy-ansible` | Type-check ansible/library and ansible/tests with mypy — files discovered via ansible/pyproject.toml | [Makefile:329](Makefile#L329) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:336](Makefile#L336) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:341](Makefile#L341) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:348](Makefile#L348) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:353](Makefile#L353) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:358](Makefile#L358) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:363](Makefile#L363) |

### Linode — credentials

| Target | Description | Source |
|---|---|---|
| `make linode-login` | Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli) | [Makefile:379](Makefile#L379) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:385](Makefile#L385) |
| `make packer-build-gateway` | Build the Alpine gateway image — generates a temporary Linode token automatically | [Makefile:390](Makefile#L390) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:398](Makefile#L398) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:404](Makefile#L404) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-volumes` | Create persistent telemetry volumes (idempotent — safe to run on an existing setup) | [Makefile:411](Makefile#L411) |
| `make dev-secrets` | Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:417](Makefile#L417) |
| `make dev-backup-secrets` | Generate secrets/dev-backup.env with GPG passphrase, S3 placeholders, and Discord notification URL | [Makefile:431](Makefile#L431) |
| `make dev-backup` | Trigger an ad-hoc backup of all dev volumes to S3; execs into the running daemon or starts a one-off instant container | [Makefile:479](Makefile#L479) |
| `make dev-restore` | Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup. | [Makefile:483](Makefile#L483) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:487](Makefile#L487) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:498](Makefile#L498) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:506](Makefile#L506) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) with scheduled backup daemon | [Makefile:516](Makefile#L516) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:521](Makefile#L521) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:526](Makefile#L526) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:534](Makefile#L534) |

