# Task 10.2D – Infrastructure, Security and Monitoring in the Pipeline

This document explains everything added on top of the Week08 project and exactly
how to run it.

## What was added / changed

| File | Change |
|---|---|
| `.github/workflows/05-terraform.yml` | **New.** Runs first, on every push to `main` (or manual dispatch): `terraform init/fmt/validate/plan/apply`. Caches `terraform.tfstate` between runs via `actions/cache` (no remote backend needed) |
| `.github/workflows/01-ci.yml` | Now triggers automatically via `workflow_run` only after `05 - Terraform Infrastructure` succeeds (instead of triggering on push directly). Added Docker Scout CVE scan + SARIF artifact upload after each image is built and pushed |
| `.github/workflows/06-monitoring.yml` | **New.** Also triggers via `workflow_run` after `05` succeeds — installs/upgrades Prometheus + Grafana (`kube-prometheus-stack` Helm chart) into AKS |
| `*-service/Dockerfile` (all 5 backend services) | Pinned base image to `python:3.12.7-slim-bookworm` + added `apt-get upgrade` to patch OS-level CVEs (remediation) |
| `frontend/Dockerfile` | Pinned `nginx:1.27-alpine` → `nginx:1.27.3-alpine` (remediation) |

## Automatic pipeline sequence

Everything now runs in order from a single `git push` to `main` — no manual triggering required:

```
push to main
      │
      ▼
05 - Terraform Infrastructure   (always runs first, provisions/updates Azure)
      │
      ├──────────────────────────────┐
      ▼                               ▼
01 - CI (test, build, Scout scan)   06 - Deploy Monitoring (Prometheus + Grafana)
      │
      ▼
02 - Deploy to Staging
      │
      ▼
03 - Test Staging
      │
      ▼
04 - Deploy to Production   (still manual — intentional, per the original design:
                              a tested build is promoted deliberately, not auto-deployed)
```

`01` and `06` both start in parallel once `05` finishes successfully, since neither depends on the other. `02`/`03` were already chained this way in Week08 and needed no changes.

## One-time setup (do this before the first push)

### 1. Make sure `AZURE_CREDENTIALS` points at a working Service Principal with access

```powershell
az account show --query id --output tsv          # your subscription ID
az ad sp credential reset --id <your-sp-appId>    # get a fresh clientSecret
az role assignment create --assignee <your-sp-appId> --role Contributor --scope /subscriptions/<subscription-id>/resourceGroups/koalatech-week06-rg
```

Update the `AZURE_CREDENTIALS` GitHub secret with:
```json
{
  "clientId": "<appId>",
  "clientSecret": "<password from credential reset>",
  "subscriptionId": "<subscription id>",
  "tenantId": "<tenant>"
}
```

### 2. Add GitHub repository secrets

Repo → **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | *(set above)* |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `JWT_SECRET_KEY`, etc. | *(already exist from Week08)* |
| `DOCKERHUB_USERNAME` | Your Docker Hub username (free account is fine) |
| `DOCKERHUB_TOKEN` | A Docker Hub access token (Docker Hub → Account Settings → Security → New Access Token) |
| `GRAFANA_ADMIN_PASSWORD` | Any password you choose for Grafana's `admin` login |

### 3. Confirm repository variables already exist (Week08)

Repo → **Settings → Secrets and variables → Actions → Variables**:
`ACR_NAME`, `ACR_LOGIN_SERVER`, `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`.

## How to run the pipeline

Just push. The whole chain runs automatically in the order shown in
"Automatic pipeline sequence" above — no manual workflow triggering needed
for `05`, `01`, `02`, `03` or `06`.

1. **Commit and push everything** (see git commands below).
2. **Watch it run:** Actions tab → you'll see `05 - Terraform Infrastructure` start immediately, then `01 - CI` and `06 - Deploy Monitoring` both start once `05` finishes, then `02 - Deploy to Staging` once `01` finishes, then `03 - Test Staging` once `02` finishes.
3. **Check Docker Scout results:** open the `01 - CI` run → each `build-and-push` matrix job → "Docker Scout - CVE scan" step for the summary, and download the `scout-report-*` artifacts for the full SARIF files.
4. **Promote to production** manually, once staging looks good: Actions tab → `04 - Deploy to Production` → **Run workflow** → paste the tested commit SHA (visible in the `02`/`03` run logs, or just use the SHA of the commit you pushed).

> First run note: the very first time you push after this change, `05` will
> create everything from scratch (resource group, ACR, storage account, AKS)
> since state was reset — this can take 10–15 minutes, mostly for AKS.
> Everything downstream waits for it automatically, so you can just let it run.

## Verifying each component (for your submission evidence)

```bash
# Confirm you're pointed at the right cluster
az aks get-credentials --resource-group koalatech-week06-rg --name mihircluster225113768 --overwrite-existing
kubectl get nodes

# Terraform outputs
cd terraform && terraform output

# Monitoring stack
kubectl get pods -n monitoring
kubectl get svc monitoring-grafana -n monitoring   # grab EXTERNAL-IP

# Grafana login
kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
# username: admin, password: either the above, or the GRAFANA_ADMIN_PASSWORD secret you set

# Application still healthy
kubectl get pods -n staging
kubectl get pods -n production
```

In Grafana (`http://<EXTERNAL-IP>`), go to **Dashboards → Import** and use ID
`315` ("Kubernetes / Views / Global") or `7249` ("Kubernetes Cluster (Prometheus)")
for an instant dashboard showing node/pod CPU, memory and cluster health — screenshot
this for submission.

## Git commands to commit and push

```bash
git add .
git commit -m "Task 10.2D: add Terraform, Docker Scout and Prometheus/Grafana to the pipeline"
git push origin main
```

## ~250-word write-up template (edit before submitting)

> Terraform was integrated as its own workflow (`05-terraform.yml`), triggered
> whenever files under `terraform/` change or manually via `workflow_dispatch`.
> It runs `fmt`, `validate`, `plan`, and `apply` against a remote Azure Storage
> backend so state persists across ephemeral GitHub-hosted runners. It was kept
> separate from the application CI pipeline because infrastructure changes are
> far less frequent than code changes and shouldn't block or be blocked by app
> builds.
>
> Docker Scout was added inside the existing `01-ci.yml` build-and-push job,
> immediately after each image is pushed to ACR and before any deployment
> happens. This places the security gate as early as possible in the pipeline
> ("shift-left"), so vulnerable images are flagged before they ever reach
> staging or production. One remediation was applied: all backend Dockerfiles
> were pinned to a specific patched Python base image tag and an
> `apt-get upgrade` step was added to patch outstanding OS-level CVEs; the
> frontend's nginx base image was similarly pinned to a newer patch release.
>
> Prometheus and Grafana were deployed via the `kube-prometheus-stack` Helm
> chart into a dedicated `monitoring` namespace, in its own workflow
> (`06-monitoring.yml`) chained after Terraform, since monitoring depends on
> the AKS cluster existing but not on any particular app release. This gives
> continuous visibility into both cluster-level metrics (node/pod CPU, memory)
> and, going forward, application-level metrics, without needing to touch the
> staging/production deploy workflows.
>
> Together these stages turn the Week08 CD pipeline into a DevSecOps pipeline:
> infrastructure is code-managed and repeatable, every image is scanned before
> release, and the running system is continuously observable.
