# GitHub App — Cross-Repo Authentication

The CI pipeline spans two repositories:

| Repo | Visibility | Role |
|---|---|---|
| `aidanhall34/cloud-infra` | Public | Source code, branch protection, commit status checks |
| `aidanhall34/homelab-deploy` | Private | Actual builds and deploys (holds Linode credentials) |

A [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) is used instead of PATs to authenticate between them. The app is installed on both repositories and mints short-lived tokens at workflow runtime via [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token).

---

## Required Permissions

The app needs the following [repository permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps):

| Permission | Level | Reason |
|---|---|---|
| **Contents** | Read | Check out `cloud-infra` source code from `homelab-deploy` runners |
| **Commit statuses** | Read & write | Post `packer-build`, `terraform-plan`, `terraform-apply` status checks back to `cloud-infra` commits |
| **Actions** | Read & write | Send `repository_dispatch` events to `homelab-deploy` from `cloud-infra` workflows |

---

## Creating the App

1. Go to **[github.com/settings/apps/new](https://github.com/settings/apps/new)** (personal account) or your organisation's equivalent.

2. Fill in the registration form:

   | Field | Value |
   |---|---|
   | **GitHub App name** | `homelab-deploy` (or any unique name) |
   | **Homepage URL** | `https://github.com/aidanhall34` |
   | **Webhook** | Uncheck **Active** — this app does not need webhooks |

3. Under **Repository permissions**, set:
   - **Contents** → `Read-only`
   - **Commit statuses** → `Read and write`
   - **Actions** → `Read and write`

   All other permissions can remain `No access`.

4. Under **Where can this GitHub App be installed?**, select **Only on this account**.

5. Click **Create GitHub App**.

6. Note the **App ID** shown at the top of the app settings page. Save it:
   ```bash
   echo "<App ID>" > secrets/github_app_id
   ```

7. Scroll down to **Private keys** and click **Generate a private key**. A `.pem` file will download automatically. Move it into place:
   ```bash
   mv ~/Downloads/<app-name>.*.private-key.pem secrets/github_app_private_key.pem
   chmod 600 secrets/github_app_private_key.pem
   ```

   See [Generating private keys for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-private-key-for-a-github-app) for more detail.

---

## Installing the App on Both Repositories

The app must be installed on `cloud-infra` **and** `homelab-deploy` before it can be granted tokens for either.

1. From the app settings page, click **Install App** in the left sidebar.

2. Click **Install** next to your account.

3. Under **Repository access**, select **Only select repositories** and choose both:
   - `aidanhall34/cloud-infra`
   - `aidanhall34/homelab-deploy`

4. Click **Install**.

See [Installing your own GitHub App](https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app) for more detail.

---

## Uploading Credentials to GitHub Actions

Once the app is created and installed, push `APP_ID` and `APP_PRIVATE_KEY` as Actions secrets to both repos:

```bash
make configure-github-app
```

This reads `secrets/github_app_id` and `secrets/github_app_private_key.pem` and uploads them to both repositories. It is idempotent — safe to re-run after rotating the private key.

---

## Deploy Approval Flow

`terraform-apply` is never triggered automatically. The approval gate lives entirely on the public `cloud-infra` side using [commit statuses](https://docs.github.com/en/rest/commits/statuses):

1. `terraform-plan` completes in `homelab-deploy` and posts two statuses to the `cloud-infra` commit:
   - `terraform-plan` → **success**
   - `terraform-apply` → **pending** ("Plan ready — trigger deploy via workflow_dispatch in cloud-infra")

2. The pending status is visible in the PR checks list. Review the plan output in the `homelab-deploy` run linked from the `terraform-plan` status.

3. When satisfied, trigger the deploy from `cloud-infra`:
   ```bash
   gh workflow run terraform-apply.yml --repo aidanhall34/cloud-infra
   ```
   Or via the GitHub UI: **Actions → terraform-apply → Run workflow**.

4. `homelab-deploy` runs the apply and resolves the `terraform-apply` status to **success** or **failure**.

If you want to require `terraform-apply` to be green before a PR can merge, add `terraform-apply` to the required status checks in `make configure-branch-protection`.

---

## Rotating the Private Key

1. Go to the app settings page → **Private keys** → **Generate a private key**.
2. Replace the local file:
   ```bash
   mv ~/Downloads/<app-name>.*.private-key.pem secrets/github_app_private_key.pem
   chmod 600 secrets/github_app_private_key.pem
   make configure-github-app
   ```
3. Delete the old key from the app settings page once the new one is confirmed working.

See [Deleting a private key](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-private-key-for-a-github-app#deleting-private-keys) for more detail.

---

## How Tokens Are Minted at Runtime

Each workflow job that needs to cross repository boundaries calls [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) scoped to only the repository it needs:

```yaml
- uses: actions/create-github-app-token@v1
  id: app-token
  with:
    app-id: ${{ secrets.APP_ID }}
    private-key: ${{ secrets.APP_PRIVATE_KEY }}
    repositories: cloud-infra   # or homelab-deploy
```

The resulting token is short-lived (1 hour), automatically revoked after the job ends, and scoped to a single repository — no long-lived PATs are stored anywhere.
