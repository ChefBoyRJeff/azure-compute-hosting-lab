# RCA-001: Scaling up an App Service plan caused about 20-30 seconds of errors

**Milestone:** M1 (App Service) · **Date:** 2026-11-02 · **Evidence:** `docs/evidence/m1-07-scale-up.txt`

## Summary
Changing the plan tier P0v3 → P1v3 and back, with one instance, caused a short outage each time: 3 of 90 probe requests failed going up (~17-20 s), 4 of 90 going down (~30 s). The portal and activity log reported the change as "Succeeded" in 1-2 seconds.

## Symptoms
- Availability probe (every ~2 s) saw a 10 s timeout and HTTP 503s, then answers from a **different instance ID**.

## Investigation
| Step | Evidence |
|---|---|
| Control-plane timing | Activity log: `Update hosting plan` Started → Succeeded in 1-2 s (16:50:43-44Z, 16:55:28-30Z) |
| Data-plane timing | Probe: failures 16:50:51-16:51:05Z (up) and 16:55:31-16:55:48Z (down) |
| Worker change | Instance ID `15c23cca` → `604bcd55` (up), `604bcd55` → `6489fea0` (down) |

## Root cause
A tier change moves the app to **new workers**. With **one instance**, nothing else could serve requests during the move. "Succeeded" describes the configuration change, not application availability.

## Remediation / prevention (production)
- Run **2 or more instances** and enable **Health check** before changing tiers (hypothesis; not tested here).
- Change tiers outside busy hours and watch an availability probe, not only the activity log.

## Lesson
Verify availability from outside. A control-plane "Succeeded" is not proof the application stayed up.
