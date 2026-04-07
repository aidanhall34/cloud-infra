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
| `make tf-init` | Initialise Terraform — generates a temporary Linode token and OBJ key automatically | [Makefile:131](Makefile#L131) |
| `make tf-init-bucket` | Create the Linode Object Storage bucket for Terraform state (idempotent — skips if bucket already exists) | [Makefile:138](Makefile#L138) |
| `make tf-plan` | Run terraform plan — generates a temporary Linode token and OBJ key automatically | [Makefile:148](Makefile#L148) |
| `make tf-deploy` | Deploy gateway — generates a temporary Linode token and OBJ key automatically | [Makefile:156](Makefile#L156) |
| `make tf-debug-bucket` | Debug: create a temp OBJ key and list the Terraform state bucket with aws s3 ls - DO NOT LOG | [Makefile:165](Makefile#L165) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:190](Makefile#L190) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:195](Makefile#L195) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:200](Makefile#L200) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:205](Makefile#L205) |

### CI — local act runs

| Target | Description | Source |
|---|---|---|
| `make ci-pre-commit` | Run the pre-commit workflow locally via act | [Makefile:214](Makefile#L214) |
| `make ci-unit-tests` | Run the unit-tests workflow locally via act | [Makefile:221](Makefile#L221) |
| `make ci-molecule` | Run the molecule workflow locally via act | [Makefile:228](Makefile#L228) |
| `make ci-packer-build` | Run the packer-build workflow locally via act (simulates push to main) | [Makefile:235](Makefile#L235) |
| `make ci-mikrotik` | Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT) | [Makefile:242](Makefile#L242) |
| `make ci-terraform-plan` | Run the terraform-plan workflow locally via act (requires TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE) | [Makefile:255](Makefile#L255) |
| `make ci-terraform-apply` | Manually run terraform-apply via act (simulates workflow_dispatch from main — requires TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE) | [Makefile:264](Makefile#L264) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make generate-wireguard-keys` | Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg) | [Makefile:275](Makefile#L275) |
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:298](Makefile#L298) |
| `make configure-branch-protection` | Configure main branch protection rules via GitHub CLI (idempotent) | [Makefile:303](Makefile#L303) |
| `make configure-github-app` | Upload GitHub App credentials (APP_ID, APP_PRIVATE_KEY) to cloud-infra and homelab-deploy | [Makefile:311](Makefile#L311) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:323](Makefile#L323) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:328](Makefile#L328) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) and git hooks | [Makefile:342](Makefile#L342) |
| `make install-hooks` | Write .git/hooks/pre-commit and make it executable | [Makefile:348](Makefile#L348) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make pre-commit` | Run all linters and unit tests (invoked by the git pre-commit hook) | [Makefile:356](Makefile#L356) |
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:359](Makefile#L359) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:362](Makefile#L362) |
| `make mypy-scripts` | Type-check scripts/ with mypy — files discovered via scripts/pyproject.toml | [Makefile:368](Makefile#L368) |
| `make mypy-ansible` | Type-check ansible/library and ansible/tests with mypy — files discovered via ansible/pyproject.toml | [Makefile:373](Makefile#L373) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:380](Makefile#L380) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:385](Makefile#L385) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:392](Makefile#L392) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:397](Makefile#L397) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:402](Makefile#L402) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:407](Makefile#L407) |

### Linode — credentials

| Target | Description | Source |
|---|---|---|
| `make linode-login` | Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli) | [Makefile:423](Makefile#L423) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:429](Makefile#L429) |
| `make packer-build-gateway` | Build the Alpine gateway image — generates a temporary Linode token automatically | [Makefile:434](Makefile#L434) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:442](Makefile#L442) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:448](Makefile#L448) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-volumes` | Create persistent telemetry volumes (idempotent — safe to run on an existing setup) | [Makefile:455](Makefile#L455) |
| `make dev-secrets` | Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:461](Makefile#L461) |
| `make dev-backup-secrets` | Generate secrets/dev-backup.env with a random GPG passphrase and S3 credential placeholders | [Makefile:475](Makefile#L475) |
| `make dev-backup` | Trigger an ad-hoc backup of all dev volumes to S3 (Prometheus TSDB snapshot taken first via exec-pre hook) | [Makefile:506](Makefile#L506) |
| `make dev-restore` | Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup. | [Makefile:510](Makefile#L510) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:514](Makefile#L514) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:525](Makefile#L525) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:533](Makefile#L533) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:543](Makefile#L543) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:548](Makefile#L548) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:553](Makefile#L553) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:561](Makefile#L561) |

