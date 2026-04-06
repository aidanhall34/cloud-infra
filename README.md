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
| `make tf-init` | Initialise Terraform with the local secrets/backend.hcl | [Makefile:58](Makefile#L58) |
| `make tf-plan` | Run terraform plan (writes plan to /tmp/tfplan.binary) | [Makefile:63](Makefile#L63) |
| `make tf-apply` | Apply the last plan produced by `make plan` | [Makefile:68](Makefile#L68) |
| `make tf-destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:73](Makefile#L73) |
| `make tf-fmt` | Run terraform fmt recursively | [Makefile:78](Makefile#L78) |
| `make tf-lint` | Check Terraform formatting without modifying files (no provider init required) | [Makefile:83](Makefile#L83) |
| `make tf-validate` | Run terraform validate (requires terraform init first) | [Makefile:88](Makefile#L88) |

### CI — local act runs

| Target | Description | Source |
|---|---|---|
| `make ci-pre-commit` | Run the pre-commit workflow locally via act | [Makefile:97](Makefile#L97) |
| `make ci-unit-tests` | Run the unit-tests workflow locally via act | [Makefile:103](Makefile#L103) |
| `make ci-molecule-gateway` | Run the molecule-gateway workflow locally via act | [Makefile:109](Makefile#L109) |
| `make ci-packer-build` | Run the packer-build workflow locally via act (requires LINODE_TOKEN) | [Makefile:115](Makefile#L115) |
| `make ci-mikrotik` | Configure MikroTik WireGuard via act (requires MIKROTIK_HOST, MIKROTIK_USERNAME, MIKROTIK_PASSWORD, MIKROTIK_WG_GATEWAY_ENDPOINT) | [Makefile:122](Makefile#L122) |
| `make ci-terraform-apply` | Manually run terraform-apply via act (requires LINODE_TOKEN, TF_STATE_*, TF_SSH_PUBLIC_KEY, TF_ALLOWED_IP_RANGE, GATEWAY_IMAGE) | [Makefile:134](Makefile#L134) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make generate-wireguard-keys` | Generate WireGuard key pairs for gateway and MikroTik (skips existing, requires wg) | [Makefile:151](Makefile#L151) |
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:174](Makefile#L174) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:179](Makefile#L179) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:184](Makefile#L184) |

### Setup

| Target | Description | Source |
|---|---|---|
| `make setup` | Install all Python dependencies (ansible/ and scripts/ virtual environments) | [Makefile:198](Makefile#L198) |

### Linting

| Target | Description | Source |
|---|---|---|
| `make lint` | Run all linters and validators (tf-validate excluded: requires terraform init) | [Makefile:206](Makefile#L206) |
| `make lint-python` | Lint all Python code with ruff (scripts/ and ansible/) | [Makefile:209](Makefile#L209) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:217](Makefile#L217) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:222](Makefile#L222) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:229](Makefile#L229) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:234](Makefile#L234) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:239](Makefile#L239) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:244](Makefile#L244) |

### Linode — credentials

| Target | Description | Source |
|---|---|---|
| `make linode-login` | Authenticate the Linode CLI via browser (writes to ~/.config/linode-cli) | [Makefile:260](Makefile#L260) |
| `make linode-packer-token` | Create a Linode packer API token expiring in 24 hours (linodes + images read/write, event read_only) - DO NOT LOG | [Makefile:264](Makefile#L264) |
| `make linode-deploy-token` | Create a Linode API token for Terraform deployments (linodes + firewall read/write) - DO NOT LOG | [Makefile:274](Makefile#L274) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins for all builds (run once after checkout) | [Makefile:286](Makefile#L286) |
| `make packer-build-gateway` | Build the Alpine gateway image (WireGuard, Blocky, Nginx) and upload it to Linode | [Makefile:291](Makefile#L291) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:297](Makefile#L297) |
| `make packer-fmt` | Format Packer configuration (all builds) | [Makefile:303](Makefile#L303) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-volumes` | Create persistent telemetry volumes (idempotent — safe to run on an existing setup) | [Makefile:310](Makefile#L310) |
| `make dev-secrets` | Generate dev Grafana admin + renderer credentials (secrets/dev-grafana.env) — skips if already present | [Makefile:316](Makefile#L316) |
| `make dev-backup-secrets` | Generate secrets/dev-backup.env with a random GPG passphrase and S3 credential placeholders | [Makefile:330](Makefile#L330) |
| `make dev-backup` | Trigger an ad-hoc backup of all dev volumes to S3 (Prometheus TSDB snapshot taken first via exec-pre hook) | [Makefile:361](Makefile#L361) |
| `make dev-restore` | Restore dev volumes from S3 (latest backup). Pass FILE=<name> to restore a specific backup. | [Makefile:365](Makefile#L365) |
| `make otelcol-validate` | Validate otelcol configs against otelcol-contrib $(OTELCOL_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:369](Makefile#L369) |
| `make blocky-validate` | Validate blocky config with blocky v$(BLOCKY_VERSION) | [Makefile:380](Makefile#L380) |
| `make prometheus-validate` | Validate prometheus config with promtool $(PROMETHEUS_VERSION) (bundled in grafana/otel-lgtm) | [Makefile:388](Makefile#L388) |
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:398](Makefile#L398) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:403](Makefile#L403) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:408](Makefile#L408) |

### Scripts container

| Target | Description | Source |
|---|---|---|
| `make build` | Build the scripts container image (aidanhall34/homelab:latest) | [Makefile:414](Makefile#L414) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:424](Makefile#L424) |

