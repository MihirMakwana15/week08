# Task 10.2D – Infrastructure, Security and Monitoring in the Pipeline

This document explains everything added on top of the Week08 project and exactly
how to run it.

## What was added / changed

| File | Change |
|---|---|
| `terraform/versions.tf` | Added an `azurerm` remote backend so Terraform state works from GitHub Actions runners |
| `.github/workflows/05-terraform.yml` | **New.** Runs `terraform init/fmt/validate/plan/apply` whenever `terraform/**` changes |
| `.github/workflows/06-monitoring.yml` | **New.** Installs/upgrades Prometheus + Grafana (`kube-prometheus-stack` Helm chart) into AKS |
| `.github/workflows/01-ci.yml` | Added Docker Scout CVE scan + SARIF artifact upload after each image is built and pushed |
| `*-service/Dockerfile` (all 5 backend services) | Pinned base image to `python:3.12.7-slim-bookworm` + added `apt-get upgrade` to patch OS-level CVEs (remediation) |
| `frontend/Dockerfile` | Pinned `nginx:1.27-alpine` → `nginx:1.27.3-alpine` (remediation) |
| `terraform/terraform.tfstate*` | Removed from the project — state now lives remotely in Azure Storage |

## One-time setup (do this before the first pipeline run)

### 1. Migrate Terraform state to the remote backend

From your own machine, with Azure CLI logged in and pointed at your subscription:

```bash
az storage container create \
  --name tfstate \
  --account-name mihirstorage225113768

cd terraform
terraform init -migrate-state
```

Answer "yes" when asked to copy existing state to the new backend.

> If you don't have a pre-existing local state (e.g. fresh clone), just run
> `terraform init` — it will create fresh state in the remote container.

### 2. Add GitHub repository secrets

Repo → **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Value |
|---|---|
| `AZURE_CREDENTIALS` | *(already exists from Week08)* |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `JWT_SECRET_KEY`, etc. | *(already exist from Week08)* |
| `DOCKERHUB_USERNAME` | Your Docker Hub username (free account is fine) |
| `DOCKERHUB_TOKEN` | A Docker Hub access token (Docker Hub → Account Settings → Security → New Access Token) |
| `GRAFANA_ADMIN_PASSWORD` | Any password you choose for Grafana's `admin` login |

### 3. Confirm repository variables already exist (Week08)

Repo → **Settings → Secrets and variables → Actions → Variables**:
`ACR_NAME`, `ACR_LOGIN_SERVER`, `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`.

## How to run the pipeline

1. **Commit and push everything** (see git commands below).
2. **Run Terraform first:** Actions tab → `05 - Terraform Infrastructure` → **Run workflow** (or just push a change under `terraform/`). Confirm it finishes green and check the "Terraform Apply" step log for evidence.
3. **Run monitoring:** Actions tab → `06 - Deploy Monitoring` → **Run workflow** (it also runs automatically after `05` succeeds). Wait for it to go green.
4. **Trigger the app pipeline:** push any small code change (or re-run `01 - CI` manually). This builds images, runs Docker Scout on each, and (via the existing `workflow_run` chain) deploys to staging, smoke-tests it, and leaves production for manual promotion exactly as in Week08.
5. **Check Docker Scout results:** open the `01 - CI` run → each `build-and-push` matrix job → "Docker Scout - CVE scan" step for the summary, and download the `scout-report-*` artifacts for the full SARIF files.
6. **Promote to production** as before: Actions tab → `04 - Deploy to Production` → **Run workflow** → paste the tested commit SHA.

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
