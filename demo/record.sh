#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# --- (0) setup -------------------------------------------------------------
export TARGET=localstack ENV_ID=demo PREVIEW_ROOT=.preview-runs/demo
# Terraform colors redirected output; the summary greps need plain text.
export TF_CLI_ARGS_plan=-no-color TF_CLI_ARGS_apply=-no-color TF_CLI_ARGS_destroy=-no-color
mkdir -p demo/out docs/assets
RUN=$(mktemp -d demo/out/run-XXXXXXXX)
export RUN
START=$(date +%s)

LS_ENV=(env -u AWS_PROFILE -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN AWS_ENDPOINT_URL=http://localhost:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 AWS_EC2_METADATA_DISABLED=true)

die() {
	echo "demo: $1" >&2
	exit 1
}

# Prints the demo environment's state list. Exits 0 with no output when the
# backend has no state object yet (terraform reports "No state file was found");
# any other terraform failure is propagated with its stderr.
state_list() {
	local out err rc
	err=$(mktemp)
	if out=$("${LS_ENV[@]}" env TF_DATA_DIR=.terraform-localstack terraform -chdir=.preview-runs/demo state list 2>"$err"); then
		rc=0
	else
		rc=$?
		if grep -q 'No state file was found' "$err"; then out=""; rc=0; else cat "$err" >&2; fi
	fi
	rm -f "$err"
	printf '%s' "$out"
	return "$rc"
}

[ "$(make print-preview-root)" = ".preview-runs/demo" ] || die "PREVIEW_ROOT did not propagate to nested make or print-preview-root failed (got: $(make print-preview-root))"

# --- (1) preflight -----------------------------------------------------------
command -v vhs >/dev/null || die "vhs is required"
command -v ffprobe >/dev/null || die "ffprobe is required"
command -v ffmpeg >/dev/null || die "ffmpeg is required"

[[ "${OPERATOR_CIDR:-}" =~ ^203\.0\.113\.[0-9]{1,3}(/[0-9]{1,2})?$ ]] || die "set OPERATOR_CIDR to a TEST-NET-3 value, e.g. OPERATOR_CIDR=203.0.113.0/24 make demo"

curl -sf localhost:4566/_localstack/health >/dev/null || die "LocalStack is not reachable on localhost:4566"

docker image inspect placeholder:local >/dev/null 2>&1 || die "placeholder:local image missing; run make placeholder-build"

"${LS_ENV[@]}" aws s3api head-bucket --bucket orbit-infra-79s5rw-tfstate >/dev/null 2>&1 || die "state bucket missing; run make bootstrap-apply TARGET=localstack first"

make render-localstack-backend >/dev/null

"${LS_ENV[@]}" env TF_DATA_DIR=.terraform-localstack terraform -chdir=.preview-runs/demo init -reconfigure -input=false >"$RUN/preflight-init.log" 2>&1 || die "terraform init failed (see $RUN/preflight-init.log)"

existing=$(state_list) || die "terraform state list failed"
[ -z "$existing" ] || die "environment demo already has state; run make destroy TARGET=localstack ENV_ID=demo first"

# --- (2) cleanup trap --------------------------------------------------------
cleanup() {
	local rc=$?
	if ! make destroy >"$RUN/cleanup.log" 2>&1; then
		echo "demo: cleanup destroy failed (see $RUN/cleanup.log)" >&2
		if [ "$rc" -eq 0 ]; then rc=1; fi
	fi
	if left=$(state_list 2>>"$RUN/cleanup.log"); then
		if [ -n "$left" ]; then
			printf '%s\n' "$left" >>"$RUN/cleanup.log"
			echo "demo: cleanup left state behind (see $RUN/cleanup.log)" >&2
			if [ "$rc" -eq 0 ]; then rc=1; fi
		fi
	else
		echo "demo: cleanup state check failed (see $RUN/cleanup.log)" >&2
		if [ "$rc" -eq 0 ]; then rc=1; fi
	fi
	exit "$rc"
}
trap cleanup EXIT

# --- (3) record ---------------------------------------------------------------
if [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
	awk '/^# DEMO-SECTION destroy/{exit} {print}' demo/demo.tape | sed "s#demo/out/#$RUN/#g" > "$RUN/demo.tape"
else
	sed "s#demo/out/#$RUN/#g" demo/demo.tape > "$RUN/demo.tape"
fi
vhs "$RUN/demo.tape"

# --- (4) failure injection ----------------------------------------------------
if [ "${DEMO_INJECT_FAIL:-}" = post-apply ]; then
	live=$(state_list) || die "state list failed"
	[ -n "$live" ] || die "injection expected live state but found none"
	echo "$live" | head -n 5
	echo "demo: injected failure after apply"
	exit 1
fi

# --- (5) assertions -------------------------------------------------------------
need() {
	[ "$1" ] || die "$2"
}

need "$([ -f "$RUN/plan.rc" ] && cat "$RUN/plan.rc")" "plan.rc missing"
[ "$(cat "$RUN/plan.rc")" = "0" ] || die "plan.rc was not 0"
need "$([ -f "$RUN/apply.rc" ] && cat "$RUN/apply.rc")" "apply.rc missing"
[ "$(cat "$RUN/apply.rc")" = "0" ] || die "apply.rc was not 0"
need "$([ -f "$RUN/destroy.rc" ] && cat "$RUN/destroy.rc")" "destroy.rc missing"
[ "$(cat "$RUN/destroy.rc")" = "0" ] || die "destroy.rc was not 0"
need "$([ -f "$RUN/status.rc" ] && cat "$RUN/status.rc")" "status.rc missing"
[ "$(cat "$RUN/status.rc")" = "0" ] || die "status.rc was not 0"
need "$([ -f "$RUN/conftest.rc" ] && cat "$RUN/conftest.rc")" "conftest.rc missing"
[ "$(cat "$RUN/conftest.rc")" = "0" ] || die "conftest.rc was not 0"

[ -f "$RUN/env.ok" ] && [ "$(cat "$RUN/env.ok")" = "1" ] || die "RUN did not reach the recorded shell"

grep -q '^Plan:' "$RUN/plan.log" || die "plan.log missing 'Plan:' line"
grep -q 'Apply complete' "$RUN/apply.log" || die "apply.log missing 'Apply complete'"
grep -q 'Destroy complete' "$RUN/destroy.log" || die "destroy.log missing 'Destroy complete'"

after=$(state_list) || die "terraform state list failed after the recorded destroy"
[ -z "$after" ] || die "state is not empty after the recorded destroy"

[ -s "$RUN/demo.gif" ] || die "demo.gif missing or empty"

gif_mtime=$(stat -f %m "$RUN/demo.gif")
[ "$gif_mtime" -ge "$START" ] || die "demo.gif mtime predates run start"

gif_size=$(stat -f %z "$RUN/demo.gif")
[ "$gif_size" -lt 4000000 ] || die "demo.gif is too large ($gif_size bytes)"

duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RUN/demo.gif")
awk -v d="$duration" 'BEGIN { if (d+0 < 30 || d+0 > 120) exit 1 }' || die "demo.gif duration $duration s out of range [30,120]"

frames=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$RUN/demo.gif")
[ "$frames" -gt 0 ] || die "demo.gif has no frames"

grep -q 'Plan: ' "$RUN/demo.txt" || die "demo.txt missing 'Plan: ' line"
grep -q 'Apply complete' "$RUN/demo.txt" || die "demo.txt missing 'Apply complete'"
grep -q 'Destroy complete' "$RUN/demo.txt" || die "demo.txt missing 'Destroy complete'"
grep -q 'PASS: conftest-gate suite' "$RUN/demo.txt" || die "demo.txt missing 'PASS: conftest-gate suite'"
grep -q '^aws_' "$RUN/demo.txt" || die "demo.txt missing state list output (no line starting with aws_)"
grep -qi 'localstack' "$RUN/demo.txt" || die "demo.txt missing localstack status output"
grep -qE '\b(ecs|elbv2|s3)\b.*(running|available)' "$RUN/demo.txt" || die "demo.txt lacks a LocalStack service row"

# --- (6) publish ---------------------------------------------------------------
mv "$RUN/demo.gif" docs/assets/demo.gif
echo "demo: docs/assets/demo.gif size=$gif_size duration=$duration frames=$frames run=$RUN"
