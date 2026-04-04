# Homelab

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
| `make init` | Initialise Terraform with the local secrets/backend.hcl | [Makefile:39](Makefile#L39) |
| `make plan` | Run terraform plan (writes plan to /tmp/tfplan.binary) | [Makefile:43](Makefile#L43) |
| `make apply` | Apply the last plan produced by `make plan` | [Makefile:47](Makefile#L47) |
| `make destroy` | Destroy all managed infrastructure (prompts for confirmation) | [Makefile:51](Makefile#L51) |
| `make fmt` | Run terraform fmt recursively | [Makefile:55](Makefile#L55) |
| `make validate` | Run terraform validate | [Makefile:59](Makefile#L59) |

### CI via act (local GitHub Actions runner)

| Target | Description | Source |
|---|---|---|
| `make ci-plan` | Run the deploy workflow (plan action) locally via act | [Makefile:65](Makefile#L65) |
| `make ci-apply` | Run the deploy workflow (apply action) locally via act | [Makefile:71](Makefile#L71) |
| `make ci-destroy` | Run the deploy workflow (destroy action) locally via act | [Makefile:77](Makefile#L77) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make upload-secrets` | Upload all secrets from secrets/ to GitHub Actions | [Makefile:85](Makefile#L85) |
| `make setup-oauth` | Create the GitHub OAuth App for Grafana SSO (writes to secrets/) | [Makefile:89](Makefile#L89) |
| `make generate-grafana-key` | Generate a new Grafana session signing key (secrets/grafana_secret_key) | [Makefile:93](Makefile#L93) |

### MikroTik router automation

| Target | Description | Source |
|---|---|---|
| `make mikrotik` | Configure MikroTik WireGuard + DNS via act (local only, not real GitHub Actions) | [Makefile:106](Makefile#L106) |

### Cloud-init boot tests

| Target | Description | Source |
|---|---|---|
| `make test-telemetry` | Boot-test the telemetry VM cloud-init (Grafana, VictoriaMetrics, Loki, Tempo) | [Makefile:124](Makefile#L124) |
| `make test-gateway` | Boot-test the gateway VM cloud-init (Blocky DNS, Nginx) | [Makefile:130](Makefile#L130) |
| `make test` | Run all cloud-init boot tests | [Makefile:136](Makefile#L136) |
| `make test-clean` | Remove all test containers left over from a local test run | [Makefile:139](Makefile#L139) |

### Python linting

| Target | Description | Source |
|---|---|---|
| `make lint` | Lint all Python code with ruff | [Makefile:145](Makefile#L145) |

### Ansible

| Target | Description | Source |
|---|---|---|
| `make ansible-lint` | Lint Ansible roles and modules with ansible-lint | [Makefile:154](Makefile#L154) |
| `make ansible-molecule` | Run molecule integration tests for all roles (Docker, systemd-compatible containers) | [Makefile:158](Makefile#L158) |
| `make ansible-pytest` | Run pytest unit tests for custom Ansible modules | [Makefile:164](Makefile#L164) |
| `make ansible-doc` | Generate documentation for all custom Ansible modules into docs/ansible-modules/ | [Makefile:168](Makefile#L168) |

### Packer — image builds

| Target | Description | Source |
|---|---|---|
| `make packer-init` | Initialise Packer plugins (run once after checkout) | [Makefile:183](Makefile#L183) |
| `make packer-build` | Build the Alpine base image and upload it to OCI | [Makefile:187](Makefile#L187) |
| `make packer-validate` | Validate Packer configuration without building | [Makefile:191](Makefile#L191) |

### Scripts container

| Target | Description | Source |
|---|---|---|
| `make build` | Build the scripts container image (aidanhall34/homelab:latest) | [Makefile:197](Makefile#L197) |

### Documentation

| Target | Description | Source |
|---|---|---|
| `make readme` | Regenerate README.md from README.md.tpl and Makefile comments | [Makefile:206](Makefile#L206) |

