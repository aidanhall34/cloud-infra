# Homelab

Infrastructure-as-code for a two-VM Oracle Cloud Always Free homelab running
WireGuard VPN, Pi-hole DNS, Grafana/VictoriaMetrics/Loki/Tempo observability,
and a MikroTik router integration.

## Available Make Targets

Run `make help` to list all targets with descriptions. Direct links into the
[Makefile](Makefile):

### Terraform — local

| Target | Description | Source |
|---|---|---|
| `make init` | Init Terraform with `secrets/backend.hcl` | [Makefile:39](Makefile#L39) |
| `make plan` | Run terraform plan | [Makefile:43](Makefile#L43) |
| `make apply` | Apply the last plan | [Makefile:47](Makefile#L47) |
| `make destroy` | Destroy all infrastructure | [Makefile:51](Makefile#L51) |
| `make fmt` | Run terraform fmt | [Makefile:55](Makefile#L55) |
| `make validate` | Run terraform validate | [Makefile:59](Makefile#L59) |

### CI via act (local GitHub Actions runner)

| Target | Description | Source |
|---|---|---|
| `make ci-plan` | Run deploy workflow (plan) locally via act | [Makefile:65](Makefile#L65) |
| `make ci-apply` | Run deploy workflow (apply) locally via act | [Makefile:71](Makefile#L71) |
| `make ci-destroy` | Run deploy workflow (destroy) locally via act | [Makefile:77](Makefile#L77) |

### Secrets and credentials

| Target | Description | Source |
|---|---|---|
| `make upload-secrets` | Upload secrets from `secrets/` to GitHub Actions | [Makefile:85](Makefile#L85) |
| `make setup-oauth` | Create GitHub OAuth App for Grafana SSO | [Makefile:89](Makefile#L89) |
| `make generate-grafana-key` | Generate Grafana session signing key | [Makefile:93](Makefile#L93) |

### MikroTik router automation

| Target | Description | Source |
|---|---|---|
| `make mikrotik` | Configure MikroTik WireGuard + DNS (local only via act) | [Makefile:106](Makefile#L106) |

### Cloud-init boot tests

| Target | Description | Source |
|---|---|---|
| `make test-telemetry` | Boot-test telemetry VM — Grafana, VictoriaMetrics, Loki, Tempo | [Makefile:122](Makefile#L122) |
| `make test-gateway` | Boot-test gateway VM — Blocky DNS, Nginx | [Makefile:128](Makefile#L128) |
| `make test` | Run all boot tests | [Makefile:133](Makefile#L133) |

## Documentation

- [docs/terraform.md](docs/terraform.md) — Terraform layout and module reference
- [docs/cloud-migration-plan.md](docs/cloud-migration-plan.md) — Migration plan
- [docs/cloud-infrastructure.md](docs/cloud-infrastructure.md) — Infrastructure overview
