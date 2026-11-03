# RCA-004: New Container Apps revision failed activation (probes on the wrong port)

**Milestone:** M2 (containers) · **Date:** 2026-11-02 · **Evidence:** `m2-03-container-apps.txt`

## Summary
After switching the app from the quickstart image (port 80) to our image (port 8080), the new revision never became healthy and ended **ActivationFailed**. The previous revision kept serving: **no user-facing outage**.

## Timeline (UTC)
| Time | Event |
|---|---|
| 18:59 | Revision `--0000001` created (our image); app log: `listening on :8080` |
| 18:59-19:02 | System log: `Probe of StartUp failed with status code: 1` x170+ |
| ~19:04 | `--0000001` = ActivationFailed; old revision still answering |
| 19:05 | Ingress target port 80 → 8080: no change |
| 19:10 | Revision restart: no change |
| ~19:16 | Probe configuration compared across revisions → root cause |
| 19:20 | New revision `--0000002` with probes on 8080: Healthy, serving |

## Root cause
The portal's "Edit and deploy" step wrote **explicit TCP probes on port 80** (the ingress port at that moment) into the new revision. Probes are **revision-scope**; the ingress target port is **application-scope**, so fixing ingress (and restarting the same revision) could not change them. My first inference ("default probes follow the ingress port") was wrong for this case and is corrected in the evidence.

## Remediation
New revision with all three probes (liveness, readiness, startup) on 8080.

## Prevention
- Declare probes explicitly in IaC with the app's port (`infra/m2.bicep`).
- Know which settings create a new revision (containers, probes, env vars, scale) and which don't (ingress, registries, secrets).
- When a fix doesn't work, compare configuration between the working and failing revisions instead of trying more fixes.
