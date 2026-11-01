# Project 6 Plan: Azure Compute and App Hosting Lab

**Status:** Plan approved 2026-11-01. M0 (scaffold, providers, budget, prices) done; nothing billable deployed yet.

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
