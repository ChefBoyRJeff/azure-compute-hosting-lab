# Project 6 Plan: Azure Compute and App Hosting Lab

**Status:** **Complete (2026-11-03).** M0-M4 done; all lab resources deleted. See the Outcomes and Deviations sections for M1-M3.

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

## M3 Outcomes and Deviations (2026-11-03)

**Deviations from the approved plan**
- **Zones 1 and 3 only:** `az vm list-skus` showed B1s (and B1ms) `NotAvailableForSubscription` in zone 2.
- **Outbound access:** the portal required an outbound option for a Flexible scale set; chose per-instance public IPs (outbound only, NSG with no inbound rules). NAT gateway is blocked by the cost policy.
- **Standard SSD** instead of Standard HDD (HDD OS disks retire September 8, 2028).
- **Planned failure turned into an investigation** (RCA-005); added autoscale diagnostic logs to Log Analytics (`law-monitoring-lab`, P2's workspace).
- **Move test** used an SSH key resource, which turned out not to support moves; recorded as a finding instead of repeated.
- **Not codified in Bicep** (time; M1/M2 already demonstrate codification with what-if).

**Measured results**

| Test | Result | Evidence |
|---|---|---|
| Zone spread | 2 instances in zones 1 and 3; new instances also in 1/3 | `m3-01`, `m3-03` |
| Inbound security | 0 custom rules; effective inbound: VNet, Azure LB, then DenyAllInBound | `m3-02` |
| Run Command | Worked with no inbound ports (33 s); outbound HTTPS 200 | `m3-02` |
| Autoscale, uneven load (run 1) | Scaled out 2→3 although raw average ~50% < 60; autoscale's observed value reached 60 | `m3-03` |
| Autoscale, uneven load (run 2) | No scale-out; observed peak 54 | `m3-04` |
| Autoscale, distributed load | Scale-out ~5 min after load start; scale-in 3→2 at 15:01:43Z; flapping protection seen in logs | `m3-05` |
| Diagnostic log latency | First evaluation rows ~37 min after the diagnostic setting was created | `m3-05` |
| Resize B1s → B1ms | 33 s including restart; 837 → 1842 MB; scale set model unchanged | `m3-06` |
| Move to another RG | Rejected: `ResourceMoveNotSupported` for `sshPublicKeys`; nothing moved | `m3-07` |
| Teardown | Both resource groups deleted; 0 tagged resources left | `m3-08` |

**Rebuild M3 (portal):** Flexible scale set, Ubuntu 24.04 Gen2, B1s, Standard SSD, zones 1 and 3, VNet `10.60.0.0/16` subnet `10.60.0.0/24`, NIC public IP enabled with NSG Basic and no inbound ports, no load balancer; then custom autoscale on Percentage CPU (out > 60 avg 5 min, in < 25, min 2 / max 3) with a diagnostic setting to Log Analytics from the start.

## M4 Outcome (2026-11-03)

- Teardown verified for every milestone (`m1-12`, `m2-06`, `m3-08`).
- Five RCAs in `docs/rca/`; interview guide in `docs/interview-guide.md`.
- Estimated project cost: M1 ~$0.20-0.25, M2 ~$0.02, M3 ~$0.10 (estimates from list prices and run times; confirm in Cost Management).

## Lab 6 Outcomes and Deviations (2026-11-05)

Added after the project was complete, as part of the AZ-104 lab series: VM operations not covered by M3 (resize and move were already done there, so they weren't repeated).

**Deviations from the plan**
- **vm-as-1 on the VNet's `default` subnet (10.3.0.0/24)**, not `snet-vm`: the portal kept its default network settings for the first VM; `vnet-lab6` ended up with two address spaces. Kept as built; the Bicep matches it.
- **Auto-shutdown notification** left on for vm-as-1 (it holds an email address), so the schedules were not codified.
- **Encryption at host enabled through the portal** after registering the feature from the CLI (subscription-level, free).
- **Default outbound access** turned out to be on; fixed through Bicep in M6 (not in the original plan).

**Predictions that were wrong (recorded)**
- Removing a VM from its availability set would be rejected: it was a **silent no-op** (exit 0, no change).
- `EncryptionAtHost` registration would take minutes: **4 s**.
- A failed extension would put the VM in a Failed provisioning state: the **VM stayed Succeeded**; only the extension failed.

**Measured results**

| Test | Result | Evidence |
|---|---|---|
| Availability set placement | vm-as-1 FD0/UD0, vm-as-2 FD1/UD1 (Aligned, 2 FD / 5 UD) | `lab6-01` |
| Change the set | Remove: silent no-op; move: `PropertyChangeNotAllowed` | `lab6-01` |
| Restart | Same physical host, temp disk kept; 35 s request to Succeeded | `lab6-02` |
| Redeploy | New host, temp disk wiped, OS disk/IP/FD/UD kept; ~1 min 41 s request to guest boot | `lab6-02` |
| Snapshot online | Incremental snapshot of a mounted disk; export disabled | `lab6-03` |
| Online expansion | 4 → 8 GiB with the VM running; guest needed a rescan, then `growpart` + `resize2fs` | `lab6-03` |
| Restore | Disk from snapshot on vm-as-2: checksum match, point-in-time contents | `lab6-03` |
| Encryption at host | Running VM rejected; deallocate → enable → start; SSE unchanged | `lab6-04` |
| Disk export | 3 of 4 disks were AllowAll (VM wizard defaults); all set to DenyAll | `lab6-04` |
| Extension failure | Detected by the CLI and the instance view, not by VM state or the portal Overview; fixed in ~8 min | `lab6-05`, RCA-006 |
| Bicep | 0 real drift; 2 fixes deployed in 36 s; outbound blocked only after deallocate/start | `lab6-06` |
| Teardown | 16 resources deleted with the resource group in ~2 min; 0 VMs, disks, snapshots left | `lab6-07` |

## Out of Scope (conceptual only)

- **Custom domains and certificates** for App Service: they need a domain you own.
- **Azure Disk Encryption** is on Microsoft's retirement path (the portal says 15 September 2028); encryption at host is the replacement and was enabled in Lab 6 M4.
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
