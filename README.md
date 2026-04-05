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

## Available Make Targets

### Terraform — local

| Target | Description | Source |
|---|---|---|
| `make init` | Initialise Terraform with the local secrets/backend.hcl | [Makefile:50](Makefile#L50) |
| `make plan` | Run terraform plan (writes plan to /tmp/tfplan.binary) | [Makefile:55](Makefile#L55) |
| `make apply` | Apply the last plan produced by `make plan` | [Makefile:60](Makefile#L60) |
| `make destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:65](Makefile#L65) |
| `make fmt` | Run terraform fmt recursively | [Makefile:70](Makefile#L70) |
| `make validate` | Run terraform validate | [Makefile:75](Makefile#L75) |

### CI via act (local GitHub Actions runner)

| Target | Description | Source |
|---|---|---|
| `make ci-plan` | Run the deploy workflow (plan action) locally via act | [Makefile:82](Makefile#L82) |
| `make ci-apply` | Run the deploy workflow (apply action) locally via act | [Makefile:89](Makefile#L89) |
| `make ci-destroy` | Run the deploy workflow (destroy action) locally via act | [Makefile:96](Makefile#L96) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:105](Makefile#L105) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:110](Makefile#L110) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:115](Makefile#L115) |

### MikroTik router automation

| Target | Description | Source |
|---|---|---|
| `make mikrotik` | Configure MikroTik WireGuard + DNS via act (local only, not real GitHub Actions) | [Makefile:129](Makefile#L129) |

### Cloud-init boot tests

| Target | Description | Source |
|---|---|---|
| `make test-telemetry` | Boot-test the telemetry VM cloud-init (Grafana, VictoriaMetrics, Loki, Tempo) | [Makefile:148](Makefile#L148) |
| `make test-gateway` | Boot-test the gateway VM cloud-init (Blocky DNS, Nginx) | [Makefile:155](Makefile#L155) |
| `make test` | Run all cloud-init boot tests | [Makefile:162](Makefile#L162) |
| `make test-clean` | Remove all test containers left over from a local test run | [Makefile:165](Makefile#L165) |

### Python linting

| Target | Description | Source |
|---|---|---|
| `make lint` | Lint all Python code with ruff | [Makefile:172](Makefile#L172) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:180](Makefile#L180) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:185](Makefile#L185) |
| `make ansible-molecule-gateway` | Run molecule integration tests for the gateway role | [Makefile:192](Makefile#L192) |
| `make ansible-molecule-common` | Run molecule integration tests for the common role | [Makefile:197](Makefile#L197) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:202](Makefile#L202) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:207](Makefile#L207) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins (run once after checkout) | [Makefile:223](Makefile#L223) |
| `make packer-build` | Build the Alpine base image and upload it to OCI | [Makefile:228](Makefile#L228) |
| `make packer-build-gateway` | Build the Alpine gateway image (WireGuard, Blocky, Nginx) and upload it to OCI | [Makefile:233](Makefile#L233) |
| `make packer-validate` | Validate all Packer configurations without building | [Makefile:238](Makefile#L238) |
| `make packer-fmt` | Format Packer configuration | [Makefile:244](Makefile#L244) |

### Development

| Target | Description | Source |
|---|---|---|
| `make dev-up` | Start the local LGTM development stack (Grafana on :3000, anonymous admin) | [Makefile:251](Makefile#L251) |
| `make dev-down` | Stop and remove the local LGTM development stack | [Makefile:256](Makefile#L256) |
| `make dev-logs` | Tail logs from all development stack services | [Makefile:261](Makefile#L261) |

### Scripts container

| Target | Description | Source |
|---|---|---|
| `make build` | Build the scripts container image (aidanhall34/homelab:latest) | [Makefile:267](Makefile#L267) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:277](Makefile#L277) |

