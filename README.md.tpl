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

<!-- MAKE_TARGETS -->
