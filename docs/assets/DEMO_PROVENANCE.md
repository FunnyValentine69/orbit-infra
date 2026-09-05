# Demo recording provenance

`docs/assets/demo.gif` is real output of a real run against LocalStack. It is rendered by `demo/record.sh` from `demo/demo.tape` (vhs) and is re-recorded, never edited.

| Field | Value |
| --- | --- |
| recorded_from | LocalStack 2026.8.1 (OrbStack), Terraform 1.16.0 |
| recorded_on | 2026-09-05 |
| generator commit | 28ceb07 (`demo/demo.tape`, `demo/record.sh`, `Makefile` targets) |
| recorder | vhs 0.11.0, ttyd 1.7.7, ffmpeg 9.0.1 |
| command | `OPERATOR_CIDR=203.0.113.0/24 make demo` from the repository root |
| environment | `ENV_ID=demo`, `TARGET=localstack`, operator CIDR `203.0.113.0/24` (TEST-NET-3; the wrapper refuses any other value) |
| plan / apply / destroy | `Plan: 59 to add, 0 to change, 0 to destroy.`; `Apply complete! Resources: 59 added, 0 changed, 0 destroyed.`; `Destroy complete! Resources: 59 destroyed.` |
| artifact | 229083 bytes, 31.04 s, 776 frames |

## What the wrapper asserted before moving the GIF into place

Every hidden step's exit code (`plan.rc`, `apply.rc`, `destroy.rc`) was 0; the plan, apply and destroy logs contain their summary lines; the environment's state list was empty before the run and empty again after the recorded destroy; the GIF was written after the run started, is under 4 MB, and has a probed duration and frame count; the vhs text dump contains the status table, the `Plan:` line, `PASS: conftest-gate suite`, `Apply complete`, at least one state-list resource and `Destroy complete`. The wrapper always runs `make destroy` on exit. Rollback was exercised with an injected failure after apply (`DEMO_INJECT_FAIL=post-apply`): live state was present when the failure fired and empty after the exit trap; a leftover-state run was refused in preflight.

## Hygiene review (what was actually checked)

- Text dump (`demo.txt`, every shown frame's text): grep for 12-digit numbers other than 000000000000, IPv4 literals outside 203.0.113.x / 127.0.0.1 / 10.x / 0.0.0.0, `/Users/`, the local username, the hostname, `@`, `AKIA`: no matches.
- Frames: `ffmpeg -fps_mode passthrough` decoded 776 frames, equal to the source count of 776; 268 unique frames by SHA-256.
- OCR: tesseract 5.5.3 over every unique frame, same grep set: no matches (the only raw hits were OCR misreads of the digit 0 as `@` in the plan and apply summary lines, checked against the frames).
- Viewed: 11 frames viewed by the reviewer (every section boundary plus a spread sample) and one frame per section by the orchestrator.

Known limits: the recorded shell is vhs's own `bash --noprofile --norc`, so no local prompt, username or hostname is typed or printed; the preview ALB group admits only the operator CIDR, so the demo shows the TEST-NET-3 dummy in the plan and nothing else environment-specific.
