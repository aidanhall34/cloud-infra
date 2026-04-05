# Homelab

> FYI - The bulk of this code is AI generated.\
> While I am doing my best to add tests etc, this an unstable project.\
> Nothing should be trusted without vetting.\
> With enough testing I may be able to remove this warning, but for now it is in rapid development, so I
> am marking it as `very unstable`

Infrastructure-as-code for a two-VM Oracle Cloud Always Free homelab running
WireGuard VPN, Pi-hole DNS, Grafana/VictoriaMetrics/Loki/Tempo observability,
and a MikroTik router integration.

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
| [Terraform](https://developer.hashicorp.com/terraform/install) | Provision Oracle Cloud infrastructure | <https://developer.hashicorp.com/terraform/install> |
| [GitHub CLI (`gh`)](https://cli.github.com/) | Upload secrets, manage PRs | <https://cli.github.com/> |
| [act](https://github.com/nektos/act) | Run GitHub Actions workflows locally | <https://github.com/nektos/act> |
| [Packer](https://developer.hashicorp.com/packer/install) | Build VM images | <https://developer.hashicorp.com/packer/install> |

After installing the tools above, run `make setup` to create the Python virtual environments.

## Available Make Targets

### Terraform — local

| Target | Description | Source |
|---|---|---|
| `make tf-init` | Initialise Terraform with the local secrets/backend.hcl | [Makefile:58](Makefile#L58) |
| `make tf-plan` | Run terraform plan (writes plan to /tmp/tfplan.binary) | [Makefile:63](Makefile#L63) |
| `make tf-apply` | Apply the last plan produced by `make plan` | [Makefile:68](Makefile#L68) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:73](Makefile#L73) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:78](Makefile#L78) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:83](Makefile#L83) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:88](Makefile#L88) |

### CI via act (local GitHub Actions runner)

| Target | Description | Source |
|---|---|---|
| `make ci-plan` | Run the deploy workflow (plan action) locally via act | [Makefile:95](Makefile#L95) |
| `make ci-apply` | Run the deploy workflow (apply action) locally via act | [Makefile:102](Makefile#L102) |
| `make ci-destroy` | Run the deploy workflow (destroy action) locally via act | [Makefile:109](Makefile#L109) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:118](Makefile#L118) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:123](Makefile#L123) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:128](Makefile#L128) |

### MikroTik router automation

| Target | Description | Source |
|---|---|---|
| `make mikrotik` | Configure MikroTik WireGuard + DNS via act (local only, not real GitHub Actions) | [Makefile:142](Makefile#L142) |

### Cloud-init boot tests

| Target | Description | Source |
|---|---|---|
| `make test-telemetry` | Boot-test the telemetry VM cloud-init (Grafana, VictoriaMetrics, Loki, Tempo) | [Makefile:161](Makefile#L161) |
| `make test-gateway` | Boot-test the gateway VM cloud-init (Blocky DNS, Nginx) | [Makefile:168](Makefile#L168) |
| `make test` | Run all cloud-init boot tests | [Makefile:175](Makefile#L175) |
| `make test-clean` | Remove all test containers left over from a local test run | [Makefile:178](Makefile#L178) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) | [Makefile:185](Makefile#L185) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:193](Makefile#L193) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:196](Makefile#L196) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:204](Makefile#L204) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:209](Makefile#L209) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:216](Makefile#L216) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:221](Makefile#L221) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:226](Makefile#L226) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:231](Makefile#L231) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:247](Makefile#L247) |
| `make packer-build` | Build the Alpine base image and upload it to OCI | [Makefile:253](Makefile#L253) |
| `make packer-build-gateway` | Build the Alpine gateway image (WireGuard, Blocky, Nginx) and upload it to OCI | [Makefile:258](Makefile#L258) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:263](Makefile#L263) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:269](Makefile#L269) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-secrets` | Generate dev Grafana admin credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:276](Makefile#L276) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:289](Makefile#L289) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:301](Makefile#L301) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:309](Makefile#L309) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:319](Makefile#L319) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:324](Makefile#L324) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:329](Makefile#L329) |

### Scripts container

| Target | Description | Source |
|---|---|---|
| `make build` | Build the scripts container image (aidanhall34/homelab:latest) | [Makefile:335](Makefile#L335) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:345](Makefile#L345) |

