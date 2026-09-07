# Demo recording provenance

`docs/assets/demo.gif` is real output of a real run against LocalStack. It is rendered by `demo/record.sh` from `demo/demo.tape` (vhs) and is re-recorded, never edited.

| Field | Value |
| --- | --- |
| recorded_from | LocalStack 2026.8.1, Terraform 1.16.0 |
| recorded_on | 2026-09-07 |
| generator commit | b42433b (the tree at this commit holds every path in DEMO_GENERATOR_PATHS) |
| recorder | vhs 0.11.0, ttyd 1.7.7-unknown, ffmpeg 9.0.1 |
| command | `OPERATOR_CIDR=203.0.113.0/24 make demo` from the repository root |
| environment | ENV_ID=demo, TARGET=localstack, workspace default, CLI config empty, operator CIDR 203.0.113.0/24 (TEST-NET-3, /24 to /32) |
| plan / apply / destroy | `Plan: 59 to add, 0 to change, 0 to destroy.`; `Apply complete! Resources: 59 added, 0 changed, 0 destroyed.`; `Destroy complete! Resources: 59 destroyed.` |
| artifact | 228173 bytes, 29.960000 s, 749 frames |
| artifact sha256 | 92697d6e2f1313c866c4677756d6485bce5df847ec10df5368368416ab3e602a |

## What the wrapper asserts before moving the GIF into place

`demo/env.sh` constructs the recorded environment from the single allowlist in `demo/lib.sh`; Bash startup files, inherited functions, unrelated variables and ambient Terraform or AWS overrides are not admitted. Before invoking any tool, the recorder requires that boundary and a CIDR network contained within `203.0.113.0/24` at prefix `/24` through `/32`. Preflight requires every declared generator path to be committed and clean, rejects ignored Terraform-consumable inputs outside runtime caches, and compares the rendered Terraform execution root with `envs/preview` in both directions.

The six tape markers (`status`, `plan`, `conftest`, `apply`, `statelist`, `destroy`) must exactly match the six generated `.rc` files and every value must be 0; `RUN` must reach the recorded shell (`env.ok`), and the plan, apply and destroy logs must contain their summary lines. The state-list command writes its exit status before its output is truncated for display. The GIF must be written after the transaction starts, be non-empty and decodable, and meet the floor derived from shown typing and sleep instructions in the same run tape. Its byte count, SHA-256, duration, frame count, summaries, versions, date, environment and generator commit are written from that run into the rows above.

After preflight, every success or failure path invokes the run-once teardown and verifies an empty Terraform state. Publication begins only after teardown succeeds; the GIF is renamed first and this provenance file second. Rollback was exercised with an injected failure after apply (`DEMO_INJECT_FAIL=post-apply`): live state was present when the failure fired, teardown ran, state was empty, and neither committed asset was replaced. A leftover-state run was refused before the teardown trap was installed.

## Hygiene review (what was actually checked)

- Text dump (`demo.txt`, every shown frame's text): grep for non-placeholder 12-digit account identifiers, IPv4 literals outside the documented TEST-NET-3, private, loopback and unspecified allowances, absolute home paths, the local username, the hostname, `@`, and `AKIA`: no matches.
- Frames: `ffmpeg` decoded all 749 frames of the artifact row (passthrough decode exit 0); 271 unique frames by MD5.
- OCR: tesseract 5.5.3 run on the reviewed recording (276 unique frames, same grep set): no matches outside 203.0.113.x and localhost; the re-recording after the review fix changed no shown command, so the text-dump grep and decode were repeated on the new artifact and the OCR pass was not.
- Viewed: 8 frames viewed by the reviewer (every section boundary plus a spread sample) and one frame per section by the orchestrator.

Known limits: the boundary does not defend against an actively hostile host, modified binaries or loader injection. Concurrent `make demo` runs are unsupported. `SIGKILL`, host crashes, and a failure of the second publish rename can leave a mixed asset pair; the final Git status and provenance contract expose that state, and a rerun repairs it. Linux is unsupported beyond the portable freshness and byte-count checks. `HOME` passes through for vhs and Docker, so provider sources implied by user-level CLI or filesystem mirror configuration are not inventoried beyond the pinned empty Terraform CLI configuration file. Any change anywhere in `DEMO_GENERATOR_PATHS` deliberately requires a new recording because infrastructure changes can alter the visible resource count.

The recorded shell is vhs's own `bash --noprofile --norc`, so no local prompt, username or hostname is typed or printed; the preview ALB group admits only the operator CIDR, so the demo shows the TEST-NET-3 dummy in the plan and nothing else environment-specific. Terraform can only destroy what it recorded in state, so an object created by a failed apply before its state write would survive cleanup and the state check; such a LocalStack leftover is cleared by restarting the emulator. OCR and frame-content review remain post-recording reviewer checks rather than CI assertions. Tool versions are recorded per run and copied into this file; the wrapper checks tool presence, not versions.
