# Interview Guide: Azure Compute and App Hosting Lab

Hands-on lab work in a personal pay-as-you-go subscription (not production). Every number below comes from `docs/evidence/`.

## 3-5 minute walkthrough

1. **Problem.** A team hosts web apps, batch jobs and APIs on the wrong platforms. I built each Azure compute option for real, changed it safely, broke it on purpose, and recorded when to choose which.
2. **App Service (M1).** Linux plan with a staging slot, sticky settings, swaps with a warm-up health check that blocked a broken build, custom CPU autoscale, a measured scale-up, and access restrictions. East US had 0 App Service quota, so I built in West US 3 and documented the quota case.
3. **Codify and verify.** I wrote Bicep for the portal build and used what-if until only documented noise remained. A config export showed the staging slot accepted plain HTTP; I fixed it through code and deployed with a production probe: 0 failed requests.
4. **Containers (M2).** Cloud-built image in ACR, ACI pulling with a user-assigned identity (denied first, diagnosed as authorization, fixed with AcrPull at registry scope), and Container Apps with a revision traffic split and an HTTP scale rule.
5. **VM Scale Set (M3).** Flexible scale set across zones 1 and 3 (zone 2 was restricted for B1s on my subscription), no inbound ports, management through Run Command, CPU autoscale with a planned failure that turned into a real investigation.
6. **Cost and cleanup.** Every milestone was torn down and verified. Estimated total under $0.50 (to confirm in Cost Management once charges post).

## 10-minute deep dive: pick one

- **Autoscale investigation (RCA-005)**: the best story. The scale-out that "shouldn't" happen did; I proved autoscale acts on its own computed value (ObservedMetricValue), which lags and differs from the metrics chart; I found flapping protection in the evaluation logs (36.69 = 24.46 × 3/2); and I fixed the real problem (undistributed load) instead of tuning thresholds.
- **Container Apps probe incident (RCA-004)**: two fixes that didn't work (ingress port, restart) led to comparing configuration across revisions; probes are revision-scope, ingress is app-scope.
- **ACI pull denied (RCA-003)**: generic error, elimination table, single-variable fix.

## Design decisions and trade-offs

| Decision | Why | Trade-off |
|---|---|---|
| P0v3 in West US 3 | East US App Service quota 0 | Region mismatch with the rest of the lab |
| Slot warm-up ping (`WEBSITE_SWAP_WARMUP_PING_*`) | Blocks a swap if `/health.php` isn't 200 | Swap takes ~70 s |
| No Log Analytics for Container Apps | Avoid ingestion cost | No stored logs (live stream only) |
| One user-assigned identity for ACI and Container Apps | ACI needs user-assigned; one AcrPull assignment | Shared identity across two workloads |
| Per-instance public IPs on the scale set, NSG with no inbound rules | Flexible scale sets have no default outbound; NAT gateway blocked by cost policy | Small hourly cost; relies on the NSG for inbound protection |
| No load balancer on the scale set | Not needed for the autoscale test | Autoscale can add instances that get no work (see RCA-005) |
| M3 not codified in Bicep | M1/M2 already show codify + what-if; VM resources produce heavy what-if noise | Scale set must be rebuilt from the README steps |

## Likely questions and answers based on what I did

- **"Scale up vs. scale out?"** Scale up changes the instance size and moved my app to a new worker (measured ~20-30 s of errors on one instance). Scale out adds instances; with autoscale it took 5 min 40 s on App Service CPU and under 20 s on Container Apps HTTP concurrency.
- **"How do slots and swaps work?"** Code moves with a swap; settings marked as slot settings stay. Phase 1 applies the target's settings to the source and warms it up; phase 2 switches routing. A warm-up ping can block the swap.
- **"Authentication vs. authorization?"** My ACI identity authenticated (valid, enabled service principal) but had no role on the registry. The fix was AcrPull at registry scope, nothing broader.
- **"Why didn't autoscale behave as expected?"** See RCA-005: check ObservedMetricValue and the evaluation logs, not the chart; enable diagnostic logs when you create the setting.
- **"Zones vs. availability sets?"** Zones are separate datacenters in a region; availability sets spread VMs over fault and update domains in one datacenter. I checked `az vm list-skus` restrictions first because B1s was blocked in zone 2 for my subscription.
- **"How do you manage VMs with no inbound ports?"** Run Command through the VM agent; access is controlled by RBAC (`virtualMachines/runCommand/action`), so it needs auditing.

## Follow-up challenges to practise

1. Your app needs zero downtime for a tier change. What would you change, and how would you prove it?
2. A Container Apps revision is ActivationFailed but the previous one is serving. What do you check first, and why not restart?
3. Why might adding a load balancer change the autoscale result in RCA-005?
4. Which settings would you add to the M2 Bicep to make a fresh deployment work in one pass?
5. What would you put in a policy to prevent the staging-slot HTTP gap from recurring?

## What I'd improve for production

- Health check + 2 instances on App Service; HTTP-based probes (`/health`) instead of TCP on Container Apps.
- Load balancer in front of the scale set; autoscale diagnostic logs from day one; alert on scale actions.
- CI/CD (as in Project 3) for the Bicep, with what-if in pull requests.
- Codify the scale set in Bicep.
