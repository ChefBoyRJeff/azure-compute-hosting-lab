# RCA-005: VM Scale Set autoscale scaled out unexpectedly (once), then didn't

**Milestone:** M3 (VM Scale Set) · **Date:** 2026-11-03 · **Evidence:** `m3-03`, `m3-04`, `m3-05`

## Planned failure
Rule: scale out when **average** CPU > 60% over 5 min. Load on **one** of two instances (~100% vs. ~0.5%), so the true average is ~50%. Expected: **no** scale-out.

## What happened
| Run | Load | Raw scale-set CPU (Metrics API) | Autoscale's own observed value | Result |
|---|---|---|---|---|
| 1 | one VM | ~50.1% every minute, 4 samples/min | climbed to **60** at 14:12Z | **Scaled out 2→3** (14:11:13Z) |
| 2 | one VM | (same setup) | peaked at **54** | No scale-out |
| Fix demo | both VMs | ~100% | 61 → 89 | Scaled out ~5 min after load start (14:51Z) |

## Investigation
- Ruled out: metric gaps (steady 4 samples/min), rule changes (threshold, aggregation, metric source, dimensions, divide-per-instance all unchanged after a 14:07 re-save).
- **Autoscale's ObservedMetricValue** (platform metric on the autoscale setting) showed autoscale evaluates **its own computed value**, which **lags** the metrics chart and differed from the raw average.
- Autoscale **evaluation logs** (Log Analytics) only started flowing ~37 min after the diagnostic setting was created, so they cover the fix demo's scale-in but not runs 1-2. They showed evaluations every ~30 s and **flapping protection**: before scale-in 3→2, the scale-out rule was evaluated at 36.69 = 24.46 × 3/2 (projected average with one fewer instance).

## Root cause
Load concentrated on one instance while autoscale decides on the **average** across instances. With a true average of ~50% and a 60% threshold, autoscale's computed value hovered at the threshold, so the outcome was **non-deterministic**. **Not determined:** exactly why run 1's evaluated value reached 60 (logs not yet flowing).

## Fix
Architectural: distribute load (load balancer or application-level distribution) so the average reflects demand. Without a load balancer, extra instances get no work anyway. Demonstrated by loading both instances: deterministic scale-out.

## Prevention
- Enable autoscale diagnostic logs **when the autoscale setting is created**, not during an incident.
- Troubleshoot autoscale with **ObservedMetricValue** and the evaluation logs, not the metrics chart.
- Keep thresholds away from the workload's normal steady state, and keep scale-in and scale-out thresholds far enough apart for flapping protection.
