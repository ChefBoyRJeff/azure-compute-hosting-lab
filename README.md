# Azure Compute and App Hosting Lab

Hands-on lab covering the main ways Azure runs workloads, and when to choose each: **App Service** (deployment slots, scaling, TLS), **containers** (Azure Container Registry, Container Instances, Container Apps), and **Virtual Machine Scale Sets** (zones and autoscale). Each part is built in the portal first, then codified in Bicep and verified with what-if, with controlled failures documented from real evidence.

Built as a hands-on project while studying for **AZ-104: Microsoft Azure Administrator**. This is lab work in a personal subscription, not a production environment.

> **Status (2026-11-02):** M0, **M1 (App Service)** and **M2 (containers)** complete and torn down. M3 (VM Scale Set) is next. Nothing is billing. Plan and measured results: [`docs/plan.md`](docs/plan.md).

## M1: App Service (done)

Built in the portal, then codified in [`infra/main.bicep`](infra/main.bicep):

- Linux App Service plan **P0v3** (West US 3, after a 0-quota block in East US) and a PHP web app
- **Staging slot** with a slot-sticky setting, swap and rollback, and a **warm-up health check** that blocks a broken build from being swapped in
- **Custom autoscale** on CPU, observed scaling out under load and back in
- **Scale up** P0v3 -> P1v3 -> P0v3 with an availability probe (measured about 20-30 s of errors on a single instance)
- **Access restrictions** tested with a reserved documentation IP (403 on production, staging unaffected)
- HTTPS only, TLS 1.2, FTPS only, basic auth disabled (deployments use Microsoft Entra ID)

**What-if** against the portal build showed **0 real drift** after two code fixes. A config export then found that the **staging slot accepted plain HTTP**; it was fixed through code and deployed with **0 failed production requests**.

### Evidence

All files are in [`docs/evidence/`](docs/evidence/) and are sanitized (subscription IDs, GUIDs, hostnames, IPs, email).

| File | Contents |
|---|---|
| `m1-00-quota-block.txt` | App Service quota of 0 in East US: timeline and outcome |
| `m1-01` .. `m1-05` | Plan and app, first deploy, slots and swap, blocked broken swap, manual scale-out |
| `m1-06-autoscale.txt` | Autoscale rules, scale-out and scale-in timeline, activity log times |
| `m1-07-scale-up.txt` | Scale-up and scale-down availability probes; autoscale caller identity |
| `m1-08-access-restrictions.txt` | 200 -> 403 -> 200 test; load endpoint removal |
| `m1-09-config-export.txt` | Live configuration export before codification; findings F1 and F2 |
| `m1-10-whatif-portal-vs-code.txt` | What-if passes 1-4 with a review of every reported change |
| `m1-11-staging-https-fix.txt` | F1 fix: what-if, deploy with production probe, before/after HTTP checks |
| `m1-12-teardown.txt` | Deletion and verification (0 resources left) |

### Rebuild

```powershell
az deployment group create -g rg-compute-lab --template-file infra/main.bicep --parameters infra/main.bicepparam
Compress-Archive app\* $env:TEMP\p6-app.zip -Force
az webapp deploy -g rg-compute-lab -n <app-name> --src-path $env:TEMP\p6-app.zip --type zip --clean true
az webapp deploy -g rg-compute-lab -n <app-name> --slot staging --src-path $env:TEMP\p6-app.zip --type zip --clean true
```

The plan bills about $0.08/hour whether or not the app is used. Delete it after testing: delete the autoscale setting, then the web app (its slot goes with it), then the plan.

## M2: Containers (done)

Codified in [`infra/m2.bicep`](infra/m2.bicep); app source in [`container/`](container/):

- **Azure Container Registry** Basic, admin user off; image built in the cloud with `az acr build` (no local Docker)
- **Azure Container Instances** pulling the private image with a **user-assigned managed identity**: first **denied** (no role), diagnosed as **authorization**, fixed with **AcrPull on the registry only**
- **Azure Container Apps** (Consumption, no log storage): private image via the same identity, ingress on 8080, **revisions and an 80/20 traffic split** (measured 80/20), **HTTP concurrency scale rule** (1 → 3 replicas in under 20 s, back to 0 after about 5 minutes)
- **Incident:** a new revision failed activation because portal-written health probes still targeted port 80; the old revision kept serving. Root cause found by comparing probe configuration across revisions; fixed with a new revision.

| Evidence | Contents |
|---|---|
| `m2-00-preflight.txt` | Providers, region availability, Container Apps and ACI quota |
| `m2-01-acr.txt` | Registry settings, cloud build, image digest |
| `m2-02-identity-and-aci-pull.txt` | Denied pull, diagnosis, AcrPull fix, running container |
| `m2-03-container-apps.txt` | Environment, app, probe incident, traffic split |
| `m2-04-scale-rule.txt` | HTTP scale rule: scale out and scale to zero |
| `m2-05-whatif.txt` | What-if of `infra/m2.bicep` against the built resources, with review |
| `m2-06-teardown.txt` | Deletion and verification |

**Rebuild (fresh):** set `pinnedRevisionName = ''` in `infra/m2.bicepparam`, deploy the registry, identity and role assignment, run `az acr build -r <acr> -t hello:v2 container`, then deploy the full template. (A single deploy fails on a fresh build because the app's first revision would try to pull an image that doesn't exist yet.)

## Repository Layout

| Path | Purpose |
|---|---|
| `infra/main.bicep`, `infra/main.bicepparam` | M1 App Service build (plan, app, slot, settings, basic auth policy, autoscale) |
| `infra/budget.bicep`, `infra/budget.example.bicepparam` | $5 budget on the resource group (real alert email kept in a gitignored local file) |
| `infra/m2.bicep`, `infra/m2.bicepparam` | M2 containers (registry, identity + AcrPull, environment, container app) |
| `container/` | Container app source (`app.py`, `Dockerfile`): reports version, revision and replica; `/health`, `/slow` |
| `app/` | Test app: `index.php` reports version, slot setting and instance; `health.php` is the swap health check |
| `docs/plan.md` | Plan, costs, outcomes and deviations |
| `docs/evidence/` | Sanitized command output for every milestone |
