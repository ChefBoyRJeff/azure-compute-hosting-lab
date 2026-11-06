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

## Lab 6: VM operations (2026-11-05)

**2-minute walkthrough.** Two B1s VMs in an availability set, managed only through Run Command. I checked where the platform placed them (fault domains 0 and 1), compared restart with redeploy from inside the VM, did a full disk cycle (attach, online snapshot, online expansion, restore to the other VM with a checksum), enabled encryption at host, broke a Custom Script Extension on purpose, then codified the build in Bicep and fixed two findings through code.

**Best stories**
- **Restart vs redeploy, proved from inside the VM.** I read the physical host name from the Hyper-V key-value exchange file (published only as a hash), and left marker files on the temp disk and the OS disk. Restart: same host, temp disk kept. Redeploy: new host, temp disk wiped, OS disk and IP kept. That's why the temp disk is scratch space only.
- **"Succeeded" isn't healthy (RCA-006).** A failed bootstrap script left the VM Succeeded / Running with no portal banner. Only the extension status showed it, and only the CLI and the instance view had the actual stderr. Lesson: monitor extension status, and make scripts idempotent.
- **Exit code 0 isn't proof.** Removing a VM from its availability set returned success and changed nothing. Moving it to another set gave the real answer: `PropertyChangeNotAllowed`.
- **A fix through code that needed one more step.** The VNet from the VM wizard had default outbound access on. What-if showed the fix (`defaultOutboundAccess: false`); after the deploy the VMs could still reach the internet until a deallocate/start, as Microsoft's docs say. I tested before and after from inside the VMs.

**Likely questions**
- **"Availability set vs availability zones?"** A set spreads VMs over fault domains (racks) and update domains (maintenance groups) in one datacenter. Zones are separate datacenters. I saw the placement (FD0/UD0, FD1/UD1) and learned the set is fixed at creation; changing it means recreating the VM and keeping its disks.
- **"When would you redeploy a VM?"** When a VM has a host-level problem that a restart doesn't fix. I measured about 1 min 41 s from request to boot; the temp disk is lost.
- **"How do you expand a disk without downtime?"** Expand it in Azure, rescan in the guest, then grow the partition and filesystem. In my lab the guest still saw 4 GiB until the rescan.
- **"SSE vs encryption at host vs ADE?"** SSE encrypts managed disks at rest and is always on. Encryption at host adds the temp disk, caches and data on its way to Storage, and needs the VM deallocated to change. ADE encrypts inside the guest, can't be combined with encryption at host, and the portal says it retires on 15 September 2028.
- **"Why mount by UUID?"** My data disk was sdc1, then sda1 after a deallocate, then sdc1 again. A device-name entry in fstab would have broken.

**Follow-up challenges to practise**
1. What changes if vm-as-1 and vm-as-2 must survive a zone failure? Which properties can't be changed in place?
2. How would you alert on a failed extension across 200 VMs?
3. Your snapshot needs to be application-consistent for a database. What do you change?
4. A team relies on default outbound access. How do you move them to private subnets without breaking them?

## What I'd improve for production

- Health check + 2 instances on App Service; HTTP-based probes (`/health`) instead of TCP on Container Apps.
- Load balancer in front of the scale set; autoscale diagnostic logs from day one; alert on scale actions.
- CI/CD (as in Project 3) for the Bicep, with what-if in pull requests.
- Codify the scale set in Bicep.
- Lab 6: an explicit outbound method (NAT gateway) if VMs need updates; extension health alerts; application-consistent backups (Azure Backup) instead of manual snapshots.
