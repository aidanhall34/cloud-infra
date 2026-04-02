# Work-Ahead Log (WAL)
# Append completed items with [DONE] and timestamp. Never delete entries.
# Resumption point: start from the first item without [DONE].

---

## Phase 1 — compute.tf / telemetry cleanup

- [DONE] `terraform/compute.tf` line 123: Remove vestigial `gateway_private_ip = ""`
      from the telemetry templatefile call. The template never references this
      variable; it was a leftover from before the DNS hostname approach.

- [DONE] `terraform/outputs.tf` line 51: In the `next_steps` output, replace the
      `private_ip` reference for Grafana access with the stable OCI internal DNS
      hostname (`local.telemetry_internal_hostname`) so the URL is valid after
      instance recreation.

---

## Phase 1b — Cloud-init boot tests [DONE 2026-04-02]

- [DONE] `scripts/render-template.py` — renders .tpl files (handles ${var}, ${indent(N,var)},
         ternary, %{ if/else/endif } directives)
- [DONE] `scripts/run-cloud-init.py` — executes a rendered cloud-init YAML on the host
         (packages → write_files → runcmd)
- [DONE] `test/vars/telemetry.json` — test variables for telemetry VM
- [DONE] `test/vars/gateway.json` — test variables for gateway VM
- [DONE] `.github/workflows/test-cloud-init.yml` — two jobs:
         test-telemetry (ubuntu-24.04-arm, checks all LGTM services)
         test-gateway (ubuntu-latest, checks Blocky DNS + Nginx)
- [DONE] `Makefile`: test-telemetry, test-gateway, test targets

---

## Phase 2 — Grafana GitHub OAuth (todo.md item 1)

- [DONE] `terraform/variables.tf`: Add `grafana_github_org` (GitHub org/user allowed
      to sign in), `grafana_admin_user` (GitHub username that becomes Admin).

- [DONE] `terraform/secrets.tf`: Add locals that read
      `secrets/grafana_github_client_id` and `secrets/grafana_github_client_secret`
      and `secrets/grafana_secret_key`.

- [DONE] `secrets/grafana_secret_key`: Generate a 64-char random hex key and write
      it to `secrets/grafana_secret_key` (gitignored, used to sign Grafana sessions).

- [DONE] `terraform/cloud-init/telemetry.yaml.tpl`: Write `/etc/grafana/grafana.ini`
      via write_files with:
        - `[auth.github]` block (enabled, client_id, client_secret, org filter,
          role_attribute_path mapping org membership to Admin)
        - `[auth] disable_login_form = true` (force GitHub SSO)
        - `[security] secret_key`, `disable_initial_admin_creation = true`
        - `[users] allow_sign_up = false`
      The grafana.ini write must come before the Grafana service starts (existing
      runcmd order already handles this — grafana-server is started after apt install).

- [DONE] `.github/workflows/deploy.yml`: Add two secret-write steps for
      `GRAFANA_GITHUB_CLIENT_ID` → `secrets/grafana_github_client_id` and
      `GRAFANA_GITHUB_CLIENT_SECRET` → `secrets/grafana_github_client_secret`.

- [DONE] `scripts/setup-github-oauth.sh`: Script that uses `gh api` to create a
      GitHub OAuth App named "Homelab Grafana" under the user/org, prints the
      client ID and secret, and saves them to `secrets/`. Requires `gh` CLI
      authenticated with `admin:org` (or personal account) scope.

- [DONE] `scripts/upload-secrets.sh`: Add the two new Grafana secrets.

---

## Phase 3 — Discord notifications (todo.md item 2)

- [DONE] `.github/workflows/deploy.yml`:
      1. Add `id: job_start` step at the top of the job that records
         `echo "time=$(date -u +%s)" >> $GITHUB_OUTPUT`.
      2. Add final step `Notify Discord` with `if: always()` that:
         - Computes duration from stored start time
         - POSTs a Discord embed via `DISCORD_WEBHOOK_URL` secret showing:
           job status (success/failure/cancelled), workflow run start date,
           action job start time, job end time, total duration.

---

## Phase 4 — Makefile + act (todo.md items 3 & 4)

- [DONE] `Makefile` (repo root): Targets with inline documentation:
        help            — lists all targets (default)
        init            — terraform init locally
        plan            — terraform plan locally
        apply           — terraform apply locally
        destroy         — terraform destroy locally
        ci-plan         — run deploy workflow plan action via act
        ci-apply        — run deploy workflow apply action via act
        ci-destroy      — run deploy workflow destroy action via act
        setup-oauth     — run scripts/setup-github-oauth.sh
        upload-secrets  — run scripts/upload-secrets.sh
        mikrotik        — run mikrotik-configure workflow via act
      act is invoked with `--secret GITHUB_TOKEN=$$GITHUB_TOKEN`.

- [DONE] `README.md`: Add "Available Make Targets" section listing every target
      with a link to its line number in the Makefile.

- [DONE] Root-level `upload-secrets.sh` (currently at repo root, duplicate of
      scripts/): Remove and replace with `make upload-secrets`.

---

## Phase 5 — docs/terraform.md (todo.md item 5)

- [DONE] `docs/terraform.md`: Explain terraform layout. Each section links to
      the relevant file (with line numbers for module blocks). Sections:
        - Overview (VCN, subnets, two Always Free VMs)
        - main.tf — provider + S3 backend
        - variables.tf — all input variables
        - secrets.tf — secrets from files pattern
        - network.tf — VCN, subnets, security lists, internet gateway
        - compute.tf — image lookup, gateway VM, telemetry VM, OCI DNS locals
        - outputs.tf — useful post-deploy values
        - cloud-init/gateway.yaml.tpl — gateway bootstrap
        - cloud-init/telemetry.yaml.tpl — telemetry bootstrap

---

## Phase 6 — MikroTik automation (todo.md item 6)

- [DONE] `.github/workflows/mikrotik-configure.yml`: Workflow that:
        - Triggers on `workflow_dispatch`
        - Has a guard step that exits if `$GITHUB_ACTIONS == true` AND
          `$ACT` is unset (i.e., running in real GitHub Actions, not act)
        - Reads SSH private key from secret `MIKROTIK_SSH_KEY` (written to
          a temp file, `chmod 600`)
        - Reads `MIKROTIK_HOST` and `MIKROTIK_USER` from secrets/vars
        - SSHes to the MikroTik and applies:
            1. WireGuard interface + peer config from vars
            2. DNS static entries from `config/pihole/local_dns.txt`

- [DONE] `Makefile`: Add `mikrotik` target that runs `act` for the
      mikrotik-configure workflow.

- [DONE] `.github/workflows/deploy.yml`: No change needed (MikroTik is separate).
