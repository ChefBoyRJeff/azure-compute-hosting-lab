# RCA-006: Custom Script Extension failed on vm-as-2 while the VM reported healthy

**Milestone:** Lab 6 M5 (controlled failure) · **Date:** 2026-11-05 (times Eastern, UTC-5) · **Evidence:** `lab6-05-extension-failure.txt`

## Summary
A bootstrap script deployed with the Custom Script Extension (CSE) copied `/etc/lab6/app.conf` into the app folder. That file is supposed to be staged before the script runs, and it never was. The script exited with status 1, and the extension reported **Provisioning failed**. The **VM itself stayed `provisioningState=Succeeded` and Running**, and the portal Overview showed no failure: the problem was visible only on the extension. The extension was uninstalled in the portal, then replaced with a corrected, idempotent script that creates its own prerequisite. It succeeded on the first run.

## Impact
App configuration on vm-as-2 was not applied for about 8 minutes (script failure 20:06:02 → corrected extension 20:13:56). The VM, its disks and its network were unaffected; Run Command and an unrelated VM change (a tag) kept working.

## Timeline
| Time (ET) | Event | Source |
|---|---|---|
| ~20:05:28 (inferred) | `az vm extension set` (CustomScript 2.1) with the broken script | CLI ran 34 s; start time not logged |
| 20:06:02 | Script fails: `cp: cannot stat '/etc/lab6/app.conf': No such file or directory`; handler logs `enable failed` | `/var/log/azure/Microsoft.Azure.Extensions.CustomScript/handler.log` (01:06:02Z) |
| 20:06 | CLI returns `VMExtensionProvisioningError` ("VM has reported a user failure ... Error code: '2'"), exit 1 | CLI |
| 20:06–20:12 | Investigation: VM state, instance view, guest logs (Run Command), portal Overview and Extensions blade | evidence §3–6, portal |
| 20:12:53 | CustomScript uninstalled in the portal (`extensions/delete` Succeeded) | activity log |
| 20:13:56 | Corrected script applied (`extensions/write` Succeeded); `/opt/lab6app/status=configured` | activity log, Run Command |

## Diagnosis: where each tool pointed
| Tool | What it showed | Useful? |
|---|---|---|
| `az vm show` provisioning state | `Succeeded` | **Misleading.** The VM was fine; the extension wasn't |
| Portal Overview | Status **Running**, no extension banner | **Misleading** in the same way |
| Portal Extensions + applications | CustomScript **Provisioning failed** | Says *which* component failed |
| Portal "View detailed status" | `ComponentStatus/ErrorClarification/failed/2`, no message | Least detail of any tool |
| CLI error / instance view message | Script stderr, exit status 1, "user failure" | **Root cause in one line** |
| Guest: `download/0/stderr`, `handler.log` | Same stderr; handler sequence `failed to execute command` → `enable failed` | Confirms it from inside the VM |

## Root cause
The script assumed a prerequisite file (`/etc/lab6/app.conf`) that nothing had created. `cp` failed, `&&` stopped the chain, and the extension reported the non-zero exit. That was a **script defect**, not a platform or agent fault: "Error code 2 ... user failure" means the extension handler ran the command correctly and the command failed.

## Remediation
1. Portal: **Extensions + applications → CustomScript → Uninstall** (only one CustomScript extension is allowed per VM).
2. Applied a corrected script that creates `/etc/lab6/app.conf` when it's missing, then copies it (safe to run again).
3. Verified: extension `Provisioning succeeded`; `/opt/lab6app/status=configured`; `app.conf=setting=1`; VM `Succeeded` / Running.

## Findings
1. **My prediction was wrong:** I expected the VM's provisioning state to become Failed. It stayed Succeeded, so a check on VM state alone misses extension failures. Monitor the extension's own status.
2. An unrelated VM update (adding a tag) succeeded while the extension was failed. The failure didn't block other management operations in this test.
3. The portal's detailed status had less information than the CLI or the instance view. For extension failures, read the instance view message first.
4. My first guest log path (`/var/log/azure/custom-script/handler.log`) was wrong. The handler logs to `/var/log/azure/Microsoft.Azure.Extensions.CustomScript/`.
5. Not explained: the failed `extensions/write` from the break never showed up in the activity log during either re-check (the delete and the corrected write did).

## Prevention
- Write bootstrap scripts to be **idempotent**, and make them check prerequisites and fail with a clear message (`[ -f file ] || { echo "missing file"; exit 1; }`).
- Stage dependencies in the same deployment (pass the file through `fileUris`, or create it in the script), and test the script on a disposable VM first.
- Alert on extension health, not only VM provisioning state: for example, Azure Resource Graph or Policy on `instanceView.extensions[].statuses[].code`.
