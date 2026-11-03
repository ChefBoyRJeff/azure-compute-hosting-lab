# RCA-002: Staging slot accepted plain HTTP

**Milestone:** M1f (Bicep codification) · **Date:** 2026-11-02 · **Evidence:** `m1-09-config-export.txt`, `m1-11-staging-https-fix.txt`

## Summary
A configuration export before writing Bicep showed `httpsOnly=false` on the **staging slot** while production was `true`. Staging answered `http://` with HTTP 200 instead of redirecting.

## Root cause
A deployment slot has its **own site configuration**. HTTPS-only (and Always On) set on production are not inherited by a slot that was not created with cloned configuration, and later production changes do not update existing slots.

## Remediation
Fixed **through code**: `stagingHttpsOnly = true` in `infra/main.bicepparam`. What-if showed exactly one real change (`httpsOnly: false => true`). Deployed with an availability probe on production: **75/75 requests HTTP 200**. After: staging `http://` → **301** to `https://`.

## Prevention
- Declare every slot's security settings explicitly in IaC.
- Export and compare slot configuration as part of reviews; don't assume slots match production.
