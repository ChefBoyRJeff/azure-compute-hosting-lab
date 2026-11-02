# Project 6 Plan: Azure Compute and App Hosting Lab

**Status:** Plan approved 2026-11-01. M0 done 2026-11-01. **M1 (App Service) and M2 (containers) done 2026-11-02**, both torn down; see the Outcomes and Deviations sections. Next: M3 (VM Scale Set).

## Business Problem

A team has to host three kinds of workloads and keeps picking the wrong platform: web apps on hand-built VMs, one-off batch jobs on always-on servers, and stateless APIs with no way to scale. This lab builds each Azure compute option for real, changes it safely, breaks it on purpose, and records when to choose which:

| Platform | Use it for | Practiced here |
|---|---|---|
| **App Service** (PaaS web hosting) | Web apps and APIs where you deploy code, not servers | Plans and tiers, scale up and out, deployment slots and swap, TLS and HTTPS, access restrictions |
| **Azure Container Instances (ACI)** | A single container on demand, billed per second | Run from a private registry with a managed identity |
| **Azure Container Apps** | Containerized apps and APIs that scale automatically, including to zero | Scale rules, revisions, traffic splitting |
| **Azure Container Registry (ACR)** | Private image storage and cloud builds | Build without local Docker (`az acr build`) |
| **Virtual Machine Scale Sets** | Identical VMs that scale with load and spread across zones | Flexible orchestration, zones, CPU autoscale, resize, move |

## Way of Working

Each milestone: **portal first** (how the exam asks about it), then **codify in Bicep** and prove the code matches with **what-if**, then capture **evidence** with read-only CLI commands. Controlled failures get an RCA.

## Milestones

| # | Milestone | Acceptance criteria | Controlled failure | Approval needed |
|---|---|---|---|---|
| M0 | Repo, providers, RG, budget, prices | Providers Registered; budget deployed, drift-clean except `@secure()` noise; prices recorded | — | Provider registration (done) |
| M1 | **App Service**: Linux plan B1, then **scale up** to S1; web app; **staging slot**; slot-sticky setting; **swap** and **swap back**; **autoscale** rule; HTTPS only, TLS 1.2; access restrictions | Each change verified from the outside (HTTP status, response content, headers); Bicep what-if matches the portal build | Broken build deployed to staging: detected before swap; then a real rollback by swapping back | S1 tier |
| M2 | **Containers**: ACR Basic; image built in the cloud; **ACI** pulling with a user-assigned managed identity; **Container Apps** (Consumption) with scale-to-zero, HTTP scale rule, revision traffic split | Container responds; scale events and revision split observed | ACI pull **denied** because the identity lacks `AcrPull`: diagnose authentication vs. authorization, fix with the narrowest role | `AcrPull` role assignment |
| M3 | **VM Scale Set**: Flexible orchestration, 2 × B1s across zones, CPU autoscale (out and in); resize a VM; move a resource to another RG; availability sets vs. zones | Scale-out and scale-in observed in autoscale history | An expected scale-out that doesn't happen, diagnosed from autoscale history and metrics | VM creation |
| M4 | Teardown, README, RCAs, interview guide | Nothing left billing; docs complete | — | Deletions |

## Cost (Azure Retail Prices API, East US, 2026-11-01)

| Item | Price | Planned use | Estimate |
|---|---|---|---|
| App Service plan B1, Linux | $0.017/hour | About 2 hours | $0.04 |
| App Service plan S1, Linux | $0.095/hour | About 3 hours (slots and autoscale need Standard) | $0.29 |
| ACR Basic | $0.1666/day | About 2 days, deleted after M2 | $0.33 |
| ACR Tasks (cloud build) | $0.0001 per vCPU-second | A few minutes | < $0.05 |
| ACI | Billed per second, about $0.00445 per GB-hour of memory plus vCPU | Under an hour, 0.5 vCPU / 1 GB | < $0.05 |
| Container Apps, Consumption | Monthly free grant; idle replicas at $0.000003 per vCPU-second | Scale to zero between tests | about $0 |
| VM Standard_B1s, Linux | $0.0104/hour each | 2–3 instances for about 2 hours | $0.06 |
| **Total** | | | **Target < $1; budget cap $5** |

**Watch-outs from the price list:**
- Container Apps shows an **Environment Management** meter at $0.10/hour. My understanding is that it applies to environments with **Dedicated** workload profiles, not Consumption-only use. **To be confirmed in M2 before creating the environment.**
- Container Apps environments can send logs to Log Analytics, which bills for ingestion. The plan is no log destination unless a test needs it.
- An App Service plan bills **whether or not apps are running**, and even when stopped. Scale down or delete it as soon as each test is done.

## Quotas and Constraints (M0 inspection)

- Regional cores 10; B-series family 10; Basv2 and Dsv5 families **0**, so the scale set uses B1s.
- Cost policy "Block costly lab resources" blocks gateways, firewalls, Bastion, NAT, App Gateway, and similar; nothing P6 needs.
- **Risk:** new pay-as-you-go subscriptions sometimes have 0 App Service quota for paid tiers. Checked first in M1.
- No Docker or GitHub CLI locally: images are built in ACR or imported.

## M1 Outcomes and Deviations (2026-11-02)

**Deviations from the approved plan**
- **Region and tier:** East US had **0 App Service quota** for every tier tried (B1, S1, F1, P0v4), so the plan was built as **P0v3 Linux in West US 3** ($0.0775/h; approved). Quota case in `m1-00`; support ticket opened.
- **Slots and autoscale on P0v3 instead of S1:** Premium v3 includes both, so the separate S1 scale-up step was replaced by a short **P0v3 -> P1v3 -> P0v3** scale-up test ($0.15/h for about 5 minutes; approved).
- **Load generator:** a temporary CPU-burn endpoint (`burn.php`) was deployed to the **staging slot only** (slots share the plan's instances, so it drives the plan's CPU metric), then removed.

**Measured results**

| Test | Result | Evidence |
|---|---|---|
| Slot swap and rollback | About 70 s per swap; sticky `LAB_SLOT` stayed with its slot | `m1-03` |
| Broken build on staging | Swap **blocked** by the warm-up ping (`/health.php` must return 200) | `m1-04` |
| Manual scale-out to 2 | Requests spread across 2 instances once keep-alive was disabled | `m1-05` |
| Custom autoscale (CPU >50% / <20%, 5 min, min 1 / max 2) | Scale-out **5 min 40 s** after load started; scale-in about 7 min after it ended; performed by the **Azure Monitor System** identity | `m1-06`, `m1-07` |
| Scale up P0v3 -> P1v3 -> P0v3 | App moved to a **new worker** each time; **about 17-20 s** (up) and **about 30 s** (down) of 503s and timeouts on a single instance | `m1-07` |
| Access restrictions | Production **403** with allow-only rule; staging stayed 200 (rules are per slot); 200 after removal | `m1-08` |
| Bicep codification | What-if: **0 real drift** after two fixes (missing tag; slot declared without `siteConfig`); remaining items documented as noise | `m1-09`, `m1-10` |
| Finding F1 fixed through code | Staging accepted plain **HTTP**; fixed with `stagingHttpsOnly=true`; deploy caused **0 failed production requests** (75/75); staging now **301 -> https** | `m1-11` |
| Teardown | Autoscale setting, app + slot, plan deleted; 0 resources left; budget kept | `m1-12` |

**Lessons recorded**
- Verify after **each** change: a combined swap + rollback runbook hid the intermediate state (`m1-03`).
- A control-plane **"Succeeded" is not app availability**: the plan update finished in 1-2 s, the outage came after it (`m1-07`).
- Slot configuration is **not inherited** from production (F1).
- Keep evidence honest: wrong log lines were corrected, not deleted (`m1-06`, `m1-08`).

**Rebuild M1:** `az deployment group create -g rg-compute-lab --template-file infra/main.bicep --parameters infra/main.bicepparam`, then deploy `app/` with `az webapp deploy` (production and staging). The app name must still be available.

## M2 Outcomes and Deviations (2026-11-02)

**Deviations from the approved plan**
- **Order:** ACI (the planned AcrPull failure) ran **before** Container Apps, so one user-assigned identity and **one** role assignment served both.
- **ACI managed-identity pulls** need a **user-assigned** identity and can only be configured with CLI/ARM/Bicep (not the portal), so that step used the CLI.
- **Environment created with the CLI** (`--logs-destination none`): the portal wizard kept proposing a new Log Analytics workspace even with "Don't save logs" selected.
- **App created from the quickstart image first**, then switched to the private image, because the portal's ACR option would have created a new identity and a second AcrPull assignment.
- Added a `/slow` endpoint to the app so the HTTP concurrency scale rule could be tested.

**Measured results**

| Test | Result | Evidence |
|---|---|---|
| Cloud build (ACR Tasks) | `hello:v1` built and pushed in 21 s; base image pinned by digest | `m2-01` |
| ACI pull without a role | `InaccessibleImage` in 3 s; no container group created | `m2-02` |
| Diagnosis | Image, network and authentication ruled out; identity had **0 roles** on the registry → **authorization** | `m2-02` |
| Fix | **AcrPull at registry scope only**; same command then succeeded (RBAC took effect within <= 288 s) | `m2-02` |
| Container Apps port/probe incident | New revision **ActivationFailed** (startup probe failed 170+ times); old revision kept serving (**no outage**). Root cause: portal-written **TCP probes on port 80** (revision scope); fixing ingress (app scope) and restarting did not help; new revision with probes on 8080 fixed it | `m2-03` |
| Traffic split | Multiple mode, 80/20 → measured **80/20** in 100 requests. Finding: the carried-over "latest revision" rule sent **100% to the new revision** before the split was set; pin traffic by name before deploying | `m2-03` |
| HTTP scale rule (concurrency 5, max 3) | **1 → 3 replicas in <= 17 s** under load; **3 → 0** about 5-6 min after load (cooldown 300 s) | `m2-04` |
| Bicep codification | What-if: **0 real drift**; role assignment shows as Create (portal random name vs. deterministic `guid()`) | `m2-05` |
| Teardown | Role assignment, app, identity, registry deleted; environment delete took ~20 min and then showed `ScheduledForDelete` | `m2-06` |

**Lessons recorded**
- Generic errors (`InaccessibleImage`) need elimination with evidence; change one variable to confirm.
- Know which settings are **revision scope** (containers, probes, env vars, scale) and which are **application scope** (ingress, registries, secrets).
- In Multiple revision mode, a new revision can take traffic immediately unless traffic is pinned by revision name.

## Out of Scope (conceptual only)

- **Custom domains and certificates** for App Service: they need a domain you own.
- **Azure Disk Encryption** is on Microsoft's retirement path; encryption at host is the replacement and is covered in the README if it can't be enabled at no cost.
- **App Service backup** needs a storage account and the Standard tier; covered if time allows during M1.

## Safety

- Separate approval before: the S1 tier, the `AcrPull` assignment, VM creation, and every deletion.
- Plans scaled down or deleted after each test; VMs deallocated or deleted; power state and plan tier checked at the end of every session.
- Evidence sanitized for subscription IDs, GUIDs, and email addresses before every commit.

## Teardown (planned before creating anything)

1. Delete the scale set and any VMs, then the ACI container group and the Container Apps app and environment.
2. Delete the ACR (images go with it) and the identity's role assignment.
3. Delete the web app and App Service plan.
4. Delete `rg-compute-lab`, then the budget after the final cost check.
