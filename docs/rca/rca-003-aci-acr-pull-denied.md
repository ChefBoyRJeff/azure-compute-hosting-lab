# RCA-003: Container Instances could not pull from the private registry

**Milestone:** M2 (containers) · **Date:** 2026-11-02 · **Evidence:** `m2-02-identity-and-aci-pull.txt` (planned failure)

## Symptom
`az container create ... --acr-identity <user-assigned identity>` failed in 3 s with `InaccessibleImage: The image ... is not accessible. Please check the image and registry credential.` No container group was created.

## Investigation (elimination)
| Possible cause | Evidence | Result |
|---|---|---|
| Wrong image or tag | `hello:v1` listed in the registry | Ruled out |
| Network | Registry public, Basic, no network rules | Ruled out |
| Authentication | Identity is an enabled `ManagedIdentity` service principal in Entra ID | Ruled out |
| **Authorization** | **0 role assignments** for the identity at registry scope | **Root cause** |

## Root cause
The identity could sign in but had **no permission** on the registry. The error message is generic and does not distinguish the cases.

## Remediation
Granted **AcrPull** (pull only) at **registry scope** only. The same command (only change: the role) succeeded; RBAC took effect within ≤288 s (not measured more precisely).

## Prevention / notes
- ACI image pulls with a managed identity require a **user-assigned** identity and can only be configured with CLI/ARM/Bicep.
- In IaC, create the role assignment before the workload (`dependsOn`), as done in `infra/m2.bicep`.
