#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
export AWS_CALL_LOG="$tmp_dir/aws-calls.log"

cat > "$tmp_dir/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$AWS_CALL_LOG"

if [[ "$*" == *vpc-stale* ]]; then
  echo 'An error occurred (InvalidVpcID.NotFound) while calling DescribeVpcs' >&2
  exit 254
fi

case "$1 $2" in
  "ec2 describe-vpcs") echo '{"Vpcs":[{"VpcId":"vpc-live"}]}' ;;
  "ec2 describe-subnets") echo '{"Subnets":[{"SubnetId":"subnet-live"}]}' ;;
  "ec2 describe-security-groups") echo '{"SecurityGroups":[{"GroupId":"sg-live"}]}' ;;
  "ec2 describe-vpc-endpoints") echo '{"VpcEndpoints":[{"VpcEndpointId":"vpce-live","State":"available"}]}' ;;
  "ec2 describe-internet-gateways") echo '{"InternetGateways":[{"InternetGatewayId":"igw-live"}]}' ;;
  "ec2 describe-route-tables") echo '{"RouteTables":[{"RouteTableId":"rtb-live"}]}' ;;
  "elbv2 describe-load-balancers") echo '{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:region:account:loadbalancer/app/lb-live/id"}]}' ;;
  "elbv2 describe-target-groups") echo '{"TargetGroups":[{"TargetGroupArn":"arn:aws:elasticloadbalancing:region:account:targetgroup/tg-live/id"}]}' ;;
  "elbv2 describe-listeners") echo '{"Listeners":[{"ListenerArn":"arn:aws:elasticloadbalancing:region:account:listener/app/lb-live/id/listener-live"}]}' ;;
  "elbv2 describe-rules") echo '{"Rules":[{"RuleArn":"arn:aws:elasticloadbalancing:region:account:listener-rule/app/lb-live/id/listener-live/rule-live"}]}' ;;
  "ecs describe-clusters") echo '{"clusters":[{"clusterArn":"arn:aws:ecs:region:account:cluster/cluster-live","status":"ACTIVE"}],"failures":[]}' ;;
  "ecs describe-services") echo '{"services":[{"serviceArn":"arn:aws:ecs:region:account:service/cluster-live/service-live","status":"ACTIVE"}],"failures":[]}' ;;
  "ecs describe-tasks") echo '{"tasks":[{"taskArn":"arn:aws:ecs:region:account:task/cluster-live/task-live","lastStatus":"RUNNING"}],"failures":[]}' ;;
  "ecs describe-task-definition")
    if [[ "$*" == *inactive-task* ]]; then
      echo '{"taskDefinition":{"taskDefinitionArn":"arn:aws:ecs:region:account:task-definition/inactive-task:1","status":"INACTIVE"}}'
    else
      echo '{"taskDefinition":{"taskDefinitionArn":"arn:aws:ecs:region:account:task-definition/active-task:1","status":"ACTIVE"}}'
    fi
    ;;
  "servicediscovery get-namespace") echo '{"Namespace":{}}' ;;
  "servicediscovery get-service") echo '{"Service":{}}' ;;
  "logs describe-log-groups") echo '{"logGroups":[{"logGroupName":"/group"}]}' ;;
  "secretsmanager describe-secret") echo '{"ARN":"secret-live"}' ;;
  "s3api head-bucket") ;;
  "sns get-topic-attributes") echo '{"Attributes":{}}' ;;
  "cloudwatch describe-alarms") echo '{"MetricAlarms":[{"AlarmName":"alarm-live"}]}' ;;
  "iam get-role") echo '{"Role":{"RoleName":"role-live"}}' ;;
  *) echo "unexpected aws call: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$tmp_dir/bin/aws"

tag_entries='[
  {"ResourceARN":"arn:aws:ec2:region:account:vpc/vpc-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:subnet/subnet-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:security-group/sg-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:vpc-endpoint/vpce-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:internet-gateway/igw-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:route-table/rtb-live","Tags":[]},
  {"ResourceARN":"arn:aws:elasticloadbalancing:region:account:loadbalancer/app/lb-live/id","Tags":[]},
  {"ResourceARN":"arn:aws:elasticloadbalancing:region:account:targetgroup/tg-live/id","Tags":[]},
  {"ResourceARN":"arn:aws:elasticloadbalancing:region:account:listener/app/lb-live/id/listener-live","Tags":[]},
  {"ResourceARN":"arn:aws:elasticloadbalancing:region:account:listener-rule/app/lb-live/id/listener-live/rule-live","Tags":[]},
  {"ResourceARN":"arn:aws:ecs:region:account:cluster/cluster-live","Tags":[]},
  {"ResourceARN":"arn:aws:ecs:region:account:service/cluster-live/service-live","Tags":[]},
  {"ResourceARN":"arn:aws:ecs:region:account:task/cluster-live/task-live","Tags":[]},
  {"ResourceARN":"arn:aws:ecs:region:account:task-definition/active-task:1","Tags":[]},
  {"ResourceARN":"arn:aws:servicediscovery:region:account:namespace/ns-live","Tags":[]},
  {"ResourceARN":"arn:aws:servicediscovery:region:account:service/srv-live","Tags":[]},
  {"ResourceARN":"arn:aws:logs:region:account:log-group:/group","Tags":[]},
  {"ResourceARN":"arn:aws:secretsmanager:region:account:secret:secret-live","Tags":[]},
  {"ResourceARN":"arn:aws:s3:::bucket-live","Tags":[]},
  {"ResourceARN":"arn:aws:sns:region:account:topic-live","Tags":[]},
  {"ResourceARN":"arn:aws:cloudwatch:region:account:alarm:alarm-live","Tags":[]},
  {"ResourceARN":"arn:aws:iam::account:role/path/role-live","Tags":[]},
  {"ResourceARN":"arn:aws:ec2:region:account:vpc/vpc-stale","Tags":[]},
  {"ResourceARN":"arn:aws:ecs:region:account:task-definition/inactive-task:1","Tags":[]}
]'

reconciled=$(TARGET=aws AWS_CLI_BIN="$tmp_dir/bin/aws" "$REPO_ROOT/scripts/reconcile-tag-inventory.sh" <<< "$tag_entries")

if [[ "$(jq '.live | length' <<< "$reconciled")" != 22 ]]; then
  echo "expected 22 live tag entries: $reconciled" >&2
  exit 1
fi
if [[ "$(jq '.stale | length' <<< "$reconciled")" != 2 ]]; then
  echo "expected two stale tag entries: $reconciled" >&2
  exit 1
fi
jq -e '.stale | map(.ResourceARN) | any(endswith("vpc/vpc-stale"))' <<< "$reconciled" >/dev/null
jq -e '.stale | map(.ResourceARN) | any(contains("task-definition/inactive-task"))' <<< "$reconciled" >/dev/null

backend_hcl="$tmp_dir/backend.aws.hcl"
BACKEND_HCL_OUT="$backend_hcl" "$REPO_ROOT/scripts/write-preview-backend.sh"
grep -Fx 'bucket       = "orbit-infra-79s5rw-tfstate"' "$backend_hcl" >/dev/null
grep -Fx 'region       = "us-east-1"' "$backend_hcl" >/dev/null
grep -Fx 'use_lockfile = true' "$backend_hcl" >/dev/null
grep -Fx 'encrypt      = true' "$backend_hcl" >/dev/null

deployer_data_policy="$(
  sed -n '/data "aws_iam_policy_document" "deployer_data"/,/resource "aws_iam_policy" "deployer_data"/p' \
    "$REPO_ROOT/bootstrap/roles.tf"
)"
for required in \
  '"ecr:GetAuthorizationToken"' \
  '"ecr:BatchGetImage"' \
  '"ecr:GetDownloadUrlForLayer"' \
  '"kms:GetPublicKey"'; do
  if ! grep -Fq "$required" <<< "$deployer_data_policy"; then
    echo "deployer role is missing image-verification permission: $required" >&2
    exit 1
  fi
done

if ! grep -Fq 'aws ecr get-login-password' "$REPO_ROOT/.github/workflows/session-apply.yml"; then
  echo "session-apply must authenticate cosign to private ECR before verification" >&2
  exit 1
fi

run_dir="$tmp_dir/preview-run"
make -C "$REPO_ROOT" render-localstack-backend \
  TARGET=localstack ENV_ID=contract PREVIEW_ROOT="$run_dir" >/dev/null
cmp "$REPO_ROOT/envs/preview/.terraform.lock.hcl" "$run_dir/.terraform.lock.hcl"

if make -C "$REPO_ROOT" check-target TARGET= >/dev/null 2>&1; then
  echo "TARGET must be required for destructive entry points" >&2
  exit 1
fi
localstack_close_recipe=$(make -n -C "$REPO_ROOT" close \
  TARGET=localstack ENV_ID=contract OPERATOR_CIDR=test-cidr PREVIEW_ROOT="$run_dir")
for required in \
  'env -u AWS_PROFILE' \
  'AWS_ENDPOINT_URL=http://localhost:4566' \
  'AWS_EC2_METADATA_DISABLED=true'; do
  if ! grep -Fq "$required" <<< "$localstack_close_recipe"; then
    echo "LocalStack close recipe is missing: $required" >&2
    exit 1
  fi
done

build_script="$REPO_ROOT/scripts/build-upstream.sh"
clickhouse_digest_line="$(grep '^clickhouse_digest:' "$REPO_ROOT/mirror-images.lock")"
repo_build_inputs_sha256="$({
  printf 'images/clickhouse/Dockerfile\n'
  cat "$REPO_ROOT/images/clickhouse/Dockerfile"
  printf '\nscripts/build-upstream.sh\n'
  cat "$build_script"
  printf '\nmirror-images.lock:clickhouse_digest\n%s\n' "$clickhouse_digest_line"
} | shasum -a 256 | awk '{print $1}')"
if [[ "$(awk '$1 == "repo_build_inputs_sha256:" { print $2 }' "$REPO_ROOT/upstream.lock")" != "$repo_build_inputs_sha256" ]]; then
  echo "upstream.lock repo_build_inputs_sha256 does not match the documented input list" >&2
  exit 1
fi

set +e
invalid_registry_out="$(UPSTREAM_DIR="$tmp_dir" PUSH=1 ECR_REGISTRY=not-an-ecr-registry \
  "$build_script" 2>&1)"
invalid_registry_rc=$?
set -e
if [[ "$invalid_registry_rc" -eq 0 ]] || \
   ! grep -Fq 'ECR_REGISTRY must be an exact private ECR registry' <<< "$invalid_registry_out"; then
  echo "PUSH=1 must reject a non-ECR registry before building" >&2
  exit 1
fi

archive_source="$tmp_dir/upstream-archive"
mkdir -p "$archive_source" "$tmp_dir/build-bin"
cat > "$archive_source/Dockerfile.api" <<'EOF'
FROM scratch
EOF
cat > "$archive_source/Dockerfile.worker" <<'EOF'
FROM scratch
EOF
printf 'SELECT 1;\n' > "$archive_source/init.sql"
archive_tar="$tmp_dir/upstream.tar"
tar -cf "$archive_tar" -C "$archive_source" .
archive_sha256="$(shasum -a 256 "$archive_tar" | awk '{print $1}')"
locked_sha="$(printf 'a%.0s' {1..40})"
build_lock="$tmp_dir/upstream.lock"
cat > "$build_lock" <<EOF
upstream_repo: SuperGokou/happyCoding
upstream_sha: $locked_sha
upstream_archive_sha256: $archive_sha256
repo_build_inputs_sha256: $repo_build_inputs_sha256

images:
  orbit-infra-79s5rw/orbit-api:
    local_id: pending
    digest: pending
  orbit-infra-79s5rw/orbit-worker:
    local_id: pending
    digest: pending
  orbit-infra-79s5rw/orbit-clickhouse:
    local_id: pending
    digest: pending
EOF

cat > "$tmp_dir/build-bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"remote get-url origin"*) echo 'https://example.invalid/SuperGokou/happyCoding.git' ;;
  *"rev-parse HEAD"*) printf '%s\n' "$FAKE_UPSTREAM_SHA" ;;
  *"status --porcelain --untracked-files=all"*) ;;
  *"archive --format=tar"*) cat "$FAKE_ARCHIVE_TAR" ;;
  *) echo "unexpected git call: $*" >&2; exit 2 ;;
esac
EOF
cat > "$tmp_dir/build-bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"image inspect --format {{.Id}}"* ]]; then
  printf 'sha256:%s\n' "$(printf 'c%.0s' {1..64})"
elif [[ "$*" == *"image inspect --format {{json .RepoDigests}}"* ]]; then
  tagged_reference="${@: -1}"
  repository_reference="${tagged_reference%:*}"
  wrong_digest="sha256:$(printf 'd%.0s' {1..64})"
  exact_digest="sha256:$(printf 'e%.0s' {1..64})"
  printf '["example.invalid/wrong@%s","%s@%s"]\n' \
    "$wrong_digest" "$repository_reference" "$exact_digest"
elif [[ "$1" == build || "$1" == tag || "$1" == push ]]; then
  :
else
  echo "unexpected docker call: $*" >&2
  exit 2
fi
EOF
chmod +x "$tmp_dir/build-bin/git" "$tmp_dir/build-bin/docker"

fake_account="$(printf '0%.0s' {1..12})"
fake_registry="${fake_account}.dkr.ecr.test-region.amazonaws.com"
build_summary="$(
  PATH="$tmp_dir/build-bin:$PATH" \
  FAKE_UPSTREAM_SHA="$locked_sha" \
  FAKE_ARCHIVE_TAR="$archive_tar" \
  UPSTREAM_DIR="$tmp_dir/fake-upstream" \
  UPSTREAM_LOCK="$build_lock" \
  PUSH=1 \
  ECR_REGISTRY="$fake_registry" \
    "$build_script"
)"
exact_digest="sha256:$(printf 'e%.0s' {1..64})"
if ! jq -e --arg digest "$exact_digest" 'all(.images[]; .digest == $digest)' <<< "$build_summary" >/dev/null; then
  echo "pushed digests must be selected by exact destination repository, not RepoDigests index" >&2
  exit 1
fi

# PR #4 overflow contracts (P0-3e): every mirror is scanned before it is
# signed, and the AWS stage-1 close runs on failure or cancellation once the
# lease exists.
mirror_workflow="$REPO_ROOT/.github/workflows/mirror-images.yml"
for mirror in redis clickhouse; do
  scan_line="$(grep -n "name: Trivy scan $mirror mirror" "$mirror_workflow" | cut -d: -f1)"
  sign_line="$(grep -n "name: KMS sign and attest $mirror mirror" "$mirror_workflow" | cut -d: -f1)"
  if [ -z "$scan_line" ] || [ -z "$sign_line" ] || [ "$scan_line" -ge "$sign_line" ]; then
    echo "mirror-images must scan the $mirror mirror before signing it (scan=$scan_line sign=$sign_line)" >&2
    exit 1
  fi
done
if ! grep -Fq "if: always() && (failure() || cancelled()) && inputs.target == 'aws'" \
    "$REPO_ROOT/.github/workflows/session-apply.yml"; then
  echo "session-apply must inspect the lease on AWS failure or cancellation without relying on step outputs" >&2
  exit 1
fi

apply_workflow="$REPO_ROOT/.github/workflows/session-apply.yml"
sweeper_workflow="$REPO_ROOT/.github/workflows/sweeper.yml"
plan_workflow="$REPO_ROOT/.github/workflows/terraform-plan.yml"
iam_matrix_workflow="${IAM_MATRIX_WORKFLOW_OVERRIDE:-$REPO_ROOT/.github/workflows/iam-matrix-plan.yml}"

if ! import_err="$(python3 -c 'import yaml' 2>&1 >/dev/null)"; then
  echo "PyYAML is required; install the version pinned by scripts/tool-version.sh pyyaml" >&2
  echo "python3 said: $(tail -n 1 <<< "$import_err")" >&2
  exit 1
fi


# Supply-chain closures: canonical SBOM comparison, hash-locked placeholder
# dependencies, scan-attestation producer ordering, scanner pinning, and apply
# freshness verification all stay offline-contractable.
bash "$REPO_ROOT/tests/sbom-canon.sh"

run_requirement_hash_contract() {
  local compiled_requirements="$1"
  python3 - "$REPO_ROOT/placeholder/requirements.in" \
    "$compiled_requirements" \
    "$REPO_ROOT/placeholder/Dockerfile" \
    "$REPO_ROOT/tools.lock" <<'PY_REQUIREMENT_HASHES'
from pathlib import Path
import re
import sys


def fail(message):
    raise SystemExit(f"FAIL: {message}")


requirements_in = Path(sys.argv[1]).read_text().splitlines()
compiled_text = Path(sys.argv[2]).read_text()
dockerfile = Path(sys.argv[3]).read_text()
tools_lock = Path(sys.argv[4]).read_text()

header = "uv pip compile --universal --generate-hashes --python-version 3.12 requirements.in -o requirements.txt"
if header not in compiled_text:
    fail("placeholder/requirements.txt must retain the uv universal hash-generation header")

logical = []
current = []
previous_ended_with_backslash = False
for raw_line in compiled_text.splitlines():
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#"):
        previous_ended_with_backslash = False
        continue
    if raw_line[:1].isspace():
        if not current:
            fail(f"placeholder/requirements.txt has a continuation line with no requirement: {stripped}")
        if not previous_ended_with_backslash:
            fail(f"placeholder/requirements.txt has an indented line that is not a continuation: {stripped}")
        current.append(stripped.rstrip("\\").strip())
        previous_ended_with_backslash = raw_line.endswith("\\")
        continue
    if current:
        logical.append(" ".join(current))
    current = [stripped.rstrip("\\").strip()]
    previous_ended_with_backslash = raw_line.endswith("\\")
if current:
    logical.append(" ".join(current))
if not logical:
    fail("placeholder/requirements.txt has no logical requirement lines")
missing_hashes = [line.split()[0] for line in logical if "--hash=sha256:" not in line]
if missing_hashes:
    fail("logical requirements lack sha256 hashes: " + ", ".join(missing_hashes))

top_level = []
for raw_line in requirements_in:
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    match = re.match(r"([A-Za-z0-9_.-]+)(?:\[[^]]+\])?==", line)
    if match is None:
        fail(f"unsupported requirements.in entry: {line}")
    top_level.append(match.group(1).lower().replace("_", "-"))
compiled_names = {
    re.match(r"([A-Za-z0-9_.-]+)(?:\[[^]]+\])?==", line).group(1).lower().replace("_", "-")
    for line in logical
}
missing_top_level = [name for name in top_level if name not in compiled_names]
if missing_top_level:
    fail("requirements.in entries missing from compiled requirements: " + ", ".join(missing_top_level))
if not re.search(r"^RUN pip install\b[^\n]*--require-hashes\b[^\n]*-r requirements\.txt$", dockerfile, re.MULTILINE):
    fail("placeholder Dockerfile must install requirements with --require-hashes")
if not re.search(r"^uv 0\.10\.4$", tools_lock, re.MULTILINE):
    fail("tools.lock must pin uv 0.10.4")
if not re.search(r"^uv b4a21408a169f66ffe2e91d4d416d5b08bd72d2780e99c700b3d79c311972a57$", tools_lock, re.MULTILINE):
    fail("tools.lock must carry the supplied uv Homebrew bottle checksum")

print(f"PASS: placeholder requirements hashes ({len(logical)} logical packages, {len(top_level)} top-level pins)")
PY_REQUIREMENT_HASHES
}

run_requirement_hash_contract "$REPO_ROOT/placeholder/requirements.txt"

requirements_continuation_mutant="$tmp_dir/requirements-continuation-before-first.txt"
python3 - "$REPO_ROOT/placeholder/requirements.txt" "$requirements_continuation_mutant" <<'PY_REQUIREMENTS_CONTINUATION_MUTANT'
from pathlib import Path
import sys


lines = Path(sys.argv[1]).read_text().splitlines(keepends=True)
for index, line in enumerate(lines):
    stripped = line.strip()
    if stripped and not stripped.startswith("#"):
        lines.insert(index, "    unhashed-demo==1.0\n")
        break
else:
    raise SystemExit("requirements continuation mutant found no first requirement")
Path(sys.argv[2]).write_text("".join(lines))
PY_REQUIREMENTS_CONTINUATION_MUTANT
set +e
requirements_continuation_output="$(run_requirement_hash_contract "$requirements_continuation_mutant" 2>&1)"
requirements_continuation_rc=$?
set -e
if [ "$requirements_continuation_rc" -eq 0 ] ||
   ! grep -Fq "FAIL: placeholder/requirements.txt has a continuation line with no requirement: unhashed-demo==1.0" \
     <<< "$requirements_continuation_output"; then
  echo "requirements continuation-before-first mutant did not fail as required: rc=$requirements_continuation_rc output=$requirements_continuation_output" >&2
  exit 1
fi
echo "PASS: placeholder requirements continuation-before-first mutant rejected"

requirements_indented_after_complete_mutant="$tmp_dir/requirements-indented-after-complete.txt"
python3 - "$REPO_ROOT/placeholder/requirements.txt" "$requirements_indented_after_complete_mutant" <<'PY_REQUIREMENTS_INDENTED_AFTER_COMPLETE_MUTANT'
from pathlib import Path
import sys


lines = Path(sys.argv[1]).read_text().splitlines(keepends=True)
for index in range(len(lines) - 1, -1, -1):
    stripped = lines[index].strip()
    if stripped and not stripped.startswith("#"):
        lines.insert(index + 1, "    unhashed-demo==1.0\n")
        break
else:
    raise SystemExit("requirements indented-after-complete mutant found no final requirement line")
Path(sys.argv[2]).write_text("".join(lines))
PY_REQUIREMENTS_INDENTED_AFTER_COMPLETE_MUTANT
set +e
requirements_indented_after_complete_output="$(
  run_requirement_hash_contract "$requirements_indented_after_complete_mutant" 2>&1
)"
requirements_indented_after_complete_rc=$?
set -e
if [ "$requirements_indented_after_complete_rc" -eq 0 ] ||
   ! grep -Fq "FAIL: placeholder/requirements.txt has an indented line that is not a continuation: unhashed-demo==1.0" \
     <<< "$requirements_indented_after_complete_output"; then
  echo "requirements indented-after-complete mutant did not fail as required: rc=$requirements_indented_after_complete_rc output=$requirements_indented_after_complete_output" >&2
  exit 1
fi
echo "PASS: placeholder requirements indented-after-complete mutant rejected"

sign_workflow="$REPO_ROOT/.github/workflows/sign-images.yml"
scan_calls_public_only_mutant="$tmp_dir/session-apply-scan-calls-public-only.yml"
attest_comment_only_mutant="$tmp_dir/sign-images-attest-comment-only.yml"
python3 - "$sign_workflow" "$mirror_workflow" "$apply_workflow" "$scan_calls_public_only_mutant" \
  "$attest_comment_only_mutant" <<'PY_SCAN_STRUCTURE'
from copy import deepcopy
from pathlib import Path
import re
import sys
import yaml


VULN_TYPE = "https://github.com/FunnyValentine69/orbit-infra/vuln-scan/v1"
TRIVY_VERSION_EXPR = "v${{ steps.tool-versions.outputs.trivy }}"


def fail(message):
    raise SystemExit(f"FAIL: {message}")


def load(path):
    value = yaml.safe_load(Path(path).read_text())
    if not isinstance(value, dict):
        fail(f"workflow is not a mapping: {path}")
    return value


def one_index(steps, predicate, label):
    matches = [index for index, step in enumerate(steps) if predicate(step)]
    if len(matches) != 1:
        fail(f"expected one {label}, found {len(matches)}")
    return matches[0]


def strip_unquoted_comment(line):
    quote = None
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote != "'":
            escaped = True
            continue
        if quote:
            if char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
        elif char == "#":
            return line[:index]
    return line


def attest_commands(run):
    commands = []
    current = None
    for physical_line in run.splitlines():
        uncommented = strip_unquoted_comment(physical_line)
        continued = uncommented.endswith("\\")
        line = uncommented.rstrip()
        if current is None:
            if re.search(r"\bcosign\s+attest(?:\s|$)", line) is None:
                continue
            current = line.strip()
        else:
            current += " " + line.strip()
        if continued:
            current = current[:-1].rstrip()
        else:
            commands.append(current)
            current = None
    if current is not None:
        commands.append(current)
    return commands


def assert_attest_flags(run, label):
    commands = attest_commands(run)
    if not commands:
        fail(f"{label} has no cosign attest command")
    for index, command in enumerate(commands, start=1):
        for flag in ("--tlog-upload=false", "--use-signing-config=false"):
            if re.search(rf"(?<!\S){re.escape(flag)}(?!\S)", command) is None:
                fail(f"{label} attest command {index} must carry {flag}")
    return len(commands)


def assert_trivy_action_version(step, label):
    if step.get("with", {}).get("version") != TRIVY_VERSION_EXPR:
        fail(f"{label} must carry the tools.lock Trivy version")


sign = load(sys.argv[1])
mirror = load(sys.argv[2])
apply = load(sys.argv[3])
sign_steps = sign["jobs"]["sign"]["steps"]
mirror_steps = mirror["jobs"]["mirror"]["steps"]
apply_steps = apply["jobs"]["apply"]["steps"]

sign_index = one_index(
    sign_steps,
    lambda step: step.get("name") == "Generate SBOMs, scan, sign, and attest upstream images",
    "upstream supply-chain step",
)
sign_step = sign_steps[sign_index]
sign_run = sign_step.get("run", "")
if sign_step.get("shell") != "bash" or not sign_run.startswith("set -euo pipefail\n"):
    fail("sign-images supply-chain step must use shell bash with explicit strict mode")
sign_attest_count = assert_attest_flags(sign_run, "sign-images supply-chain step")
mirror_attest_count = 0
for step in mirror_steps:
    step_run = step.get("run", "")
    if attest_commands(step_run):
        mirror_attest_count += assert_attest_flags(
            step_run,
            f"mirror-images {step.get('name', 'unnamed step')}",
        )
if mirror_attest_count == 0:
    fail("mirror-images has no cosign attest commands")
print(
    f"PASS: attest command flags ({sign_attest_count} sign-images commands, "
    f"{mirror_attest_count} mirror-images commands)"
)
slurp_decode = "jq -c -s '.[] | (.payload | @base64d | fromjson | .predicate)'"
if slurp_decode not in sign_run:
    fail("sign-images prior-attestation decode must slurp the complete verification stream")
if "jq -c '(.payload" in sign_run:
    fail("sign-images prior-attestation decode must not use the non-slurp form")
print("PASS: sign-images prior-attestation slurp decode structure")
if "done < <(jq" in sign_run:
    fail("sign-images must decode prior attestations before entering the predicate loop")
for marker in (
    "could not decode attestations",
    "current SBOM canonicalization failed",
    "prior SBOM canonicalization failed; re-attesting",
):
    if marker not in sign_run:
        fail(f"sign-images lacks fail-closed SBOM guard diagnostic: {marker}")
if '.name + "@" + (.versionInfo // "")' in sign_run:
    fail("sign-images must not retain the name@version SBOM inventory filter")
if sign_run.count("scripts/sbom-canon.sh") < 2:
    fail("sign-images must canonicalise the new SBOM and every decoded prior predicate")
sign_markers = (
    'trivy image --platform linux/arm64 --severity CRITICAL --exit-code 1',
    '--type spdxjson --predicate',
    f"--type {VULN_TYPE}",
    "cosign sign --yes",
)
positions = [sign_run.find(marker) for marker in sign_markers]
if any(position < 0 for position in positions) or positions != sorted(positions):
    fail("sign-images order must be Trivy, SBOM attest, scan attest, signature")
for field in ("scanner", "trivyVersion", "severityGate", "exitCode", "scannedAt", "digest"):
    if field not in sign_run:
        fail(f"sign-images vulnerability predicate lacks {field}")

artifacts = (
    ("placeholder", "KMS sign and attest placeholder"),
    ("redis mirror", "KMS sign and attest redis mirror"),
    ("clickhouse mirror", "KMS sign and attest clickhouse mirror"),
)
for artifact, sign_name in artifacts:
    scan_name = f"Trivy scan {artifact}"
    attest_name = f"Attest vulnerability scan {artifact}"
    scan_step_index = one_index(mirror_steps, lambda step, name=scan_name: step.get("name") == name, scan_name)
    attest_step_index = one_index(mirror_steps, lambda step, name=attest_name: step.get("name") == name, attest_name)
    image_sign_index = one_index(mirror_steps, lambda step, name=sign_name: step.get("name") == name, sign_name)
    if not scan_step_index < attest_step_index < image_sign_index:
        fail(f"mirror-images order must be Trivy, scan attest, signature for {artifact}")
    scan_step = mirror_steps[scan_step_index]
    if not str(scan_step.get("uses", "")).startswith("aquasecurity/trivy-action@"):
        fail(f"{scan_name} must use trivy-action")
    assert_trivy_action_version(scan_step, scan_name)
    severity_expression = scan_step.get("with", {}).get("severity")
    if severity_expression != "${{ env.TRIVY_SEVERITY_GATE }}":
        fail(f"{scan_name} must read the shared TRIVY_SEVERITY_GATE")
    attest_run = mirror_steps[attest_step_index].get("run", "")
    assert_attest_flags(attest_run, attest_name)
    if f"--type {VULN_TYPE}" not in attest_run:
        fail(f"{attest_name} must use the vulnerability predicate type")
    for field in ("scanner", "trivyVersion", "severityGate", "exitCode", "scannedAt", "digest"):
        if field not in attest_run:
            fail(f"{attest_name} predicate lacks {field}")
    if "trivy --version" not in attest_run or "trivy version mismatch" not in attest_run:
        fail(f"{attest_name} must attest the executed binary version after checking the pin")
    if '--arg severity_gate "$TRIVY_SEVERITY_GATE"' not in attest_run:
        fail(f"{attest_name} must attest the shared TRIVY_SEVERITY_GATE")

mirror_gate = mirror["jobs"]["mirror"].get("env", {}).get("TRIVY_SEVERITY_GATE")
if mirror_gate != "CRITICAL,HIGH":
    fail("mirror-images must define the shared CRITICAL,HIGH severity gate once at job scope")

first_attest = next(step for step in mirror_steps if step.get("name") == "Attest vulnerability scan placeholder")
for removed_flag in ("--tlog-upload=false", "--use-signing-config=false"):
    mutant = first_attest["run"].replace(removed_flag, "", 1)
    try:
        assert_attest_flags(mutant, "mutated placeholder vulnerability attestation")
    except SystemExit:
        pass
    else:
        fail(f"scan-attestation flag mutant survived removal of {removed_flag}")
print("PASS: scan-attestation flag mutants killed (2 mutations)")

sign_source = Path(sys.argv[1]).read_text()
attest_anchor = "              cosign attest --yes --tlog-upload=false --use-signing-config=false " + "\\"
attest_replacement = (
    "              # --tlog-upload=false\n"
    "              cosign attest --yes --use-signing-config=false " + "\\"
)
if attest_anchor not in sign_source:
    fail("comment-only attest flag mutation anchor missing")
Path(sys.argv[5]).write_text(sign_source.replace(attest_anchor, attest_replacement, 1))
mutated_sign = load(sys.argv[5])
mutated_sign_steps = mutated_sign["jobs"]["sign"]["steps"]
mutated_sign_step = next(
    step
    for step in mutated_sign_steps
    if step.get("name") == "Generate SBOMs, scan, sign, and attest upstream images"
)
try:
    assert_attest_flags(mutated_sign_step["run"], "comment-only flag mutant")
except SystemExit as exc:
    if "--tlog-upload=false" not in str(exc):
        raise
else:
    fail("comment-only attest flag mutant survived")
print("PASS: comment-only attest flag mutant killed")

mutated_mirror = deepcopy(mirror_steps)
mutated_scan = next(step for step in mutated_mirror if step.get("name") == "Trivy scan placeholder")
mutated_scan["with"]["version"] = "v0.0.0"
try:
    assert_trivy_action_version(mutated_scan, "mutated placeholder Trivy step")
except SystemExit:
    pass
else:
    fail("divergent Trivy version mutant survived validation")
print("PASS: divergent trivy-action version fixture rejected")

trigger = mirror.get("on", mirror.get(True))
cron_entries = trigger.get("schedule") if isinstance(trigger, dict) else None
cron_values = [entry.get("cron") for entry in cron_entries or [] if isinstance(entry, dict)]
if cron_values != ["0 6 * * 1"]:
    fail(f"mirror-images schedule must be Monday 06:00 UTC weekly, found {cron_values}")

apply_trigger = apply.get("on", apply.get(True))
inputs = apply_trigger.get("workflow_dispatch", {}).get("inputs", {}) if isinstance(apply_trigger, dict) else {}
freshness = inputs.get("scan_freshness_days")
default_days = freshness.get("default") if isinstance(freshness, dict) else None
if default_days != 10:
    fail("session-apply scan_freshness_days must default to 10")
cron_parts = cron_values[0].split()
if cron_parts != ["0", "6", "*", "*", "1"]:
    fail("mirror-images cadence parser requires the Monday 06:00 UTC weekly cron")
scheduled_interval_days = 7
if default_days < scheduled_interval_days + 3:
    fail("scan freshness default must cover the parsed producer interval plus three days")

verify_index = one_index(
    apply_steps,
    lambda step: step.get("name") == "Verify selected image signatures and attestations",
    "session-apply image verification step",
)
verify_step = apply_steps[verify_index]
verify_run = verify_step.get("run", "")
if verify_step.get("shell") != "bash" or not verify_run.startswith("set -euo pipefail\n"):
    fail("session-apply image verification step must use shell bash with explicit strict mode")
if "done < <(jq" in verify_run:
    fail("session-apply must decode scan attestations before entering the predicate loop")
if "could not decode attestations" not in verify_run:
    fail("session-apply lacks the malformed-attestation decode diagnostic")
if "verify_scan_attestation()" not in verify_run:
    fail("session-apply must define verify_scan_attestation")
def extract_mode_branches(run):
    lines = run.splitlines()
    case_indexes = [
        index
        for index, line in enumerate(lines)
        if re.fullmatch(r'\s*case\s+"?\$\{?MODE\}?"?\s+in\s*', line)
    ]
    if len(case_indexes) == 1:
        branches = {"upstream": [], "public": []}
        current = None
        found_esac = False
        for line in lines[case_indexes[0] + 1 :]:
            label = re.fullmatch(r"\s*(upstream|public)\)\s*", line)
            if label:
                current = label.group(1)
                continue
            if re.fullmatch(r"\s*;;\s*", line):
                current = None
                continue
            if re.fullmatch(r"\s*esac\s*", line):
                found_esac = True
                break
            if current:
                branches[current].append(line)
        if not found_esac or any(not branch for branch in branches.values()):
            fail("session-apply deployment mode case must have non-empty upstream and public branches")
        return branches
    if case_indexes:
        fail(f"session-apply must have one deployment mode case, found {len(case_indexes)}")

    starts = [
        index
        for index, line in enumerate(lines)
        if re.match(r'^\s*if\s+\[\[?.*\$\{?MODE\}?.*upstream.*;\s*then\s*$', line)
    ]
    if len(starts) != 1:
        fail("session-apply must guard scan verification with a deployment mode case or if/else")
    start = starts[0]
    else_indexes = [index for index in range(start + 1, len(lines)) if re.fullmatch(r"\s*else\s*", lines[index])]
    fi_indexes = [index for index in range(start + 1, len(lines)) if re.fullmatch(r"\s*fi\s*", lines[index])]
    if not else_indexes or not fi_indexes or not start < else_indexes[0] < fi_indexes[0]:
        fail("session-apply deployment mode if/else branches are malformed")
    return {
        "upstream": lines[start + 1 : else_indexes[0]],
        "public": lines[else_indexes[0] + 1 : fi_indexes[0]],
    }


def selected_images(branch):
    selected = []
    patterns = (
        r"^\s*verify_(?:upstream|mirror)_attestation\s+([a-z_]+)\s+",
        r'^\s*verify_placeholder_attestation\s+"\$([a-z_]+)"\s*$',
    )
    for line in branch:
        for pattern in patterns:
            match = re.match(pattern, line)
            if match:
                selected.append(match.group(1))
                break
    if not selected:
        fail("session-apply deployment mode branch selects no images")
    if len(selected) != len(set(selected)):
        fail(f"session-apply deployment mode branch selects an image more than once: {selected}")
    return selected


def assert_mode_scan_calls(run):
    branches = extract_mode_branches(run)
    counts = {}
    for mode, branch in branches.items():
        expected = selected_images(branch)
        branch_text = "\n".join(branch)
        for label in expected:
            call = f'verify_scan_attestation {label} "${label}"'
            count = branch_text.count(call)
            if count != 1:
                fail(f"session-apply {mode} branch must contain one scan call for {label}, found {count}")
        scan_calls = re.findall(r"^\s*verify_scan_attestation\s+([a-z_]+)\s+", branch_text, re.MULTILINE)
        if sorted(scan_calls) != sorted(expected):
            fail(f"session-apply {mode} branch scan calls do not match selected images")
        counts[mode] = len(scan_calls)
    return counts


mode_scan_counts = assert_mode_scan_calls(verify_run)
print(
    "PASS: scan verification call sites "
    f"(upstream={mode_scan_counts['upstream']}, public={mode_scan_counts['public']})"
)

mutated_apply = deepcopy(apply)
mutated_steps = mutated_apply["jobs"]["apply"]["steps"]
mutated_verify = next(
    step for step in mutated_steps if step.get("name") == "Verify selected image signatures and attestations"
)
mutant_lines = []
in_mode_case = False
current_mode = None
for line in mutated_verify["run"].splitlines():
    if re.fullmatch(r'\s*case\s+"?\$\{?MODE\}?"?\s+in\s*', line):
        in_mode_case = True
    label = re.fullmatch(r"\s*(upstream|public)\)\s*", line) if in_mode_case else None
    if label:
        current_mode = label.group(1)
    if not (current_mode == "upstream" and re.match(r"^\s*verify_scan_attestation\s+", line)):
        mutant_lines.append(line)
    if in_mode_case and re.fullmatch(r"\s*;;\s*", line):
        current_mode = None
    if in_mode_case and re.fullmatch(r"\s*esac\s*", line):
        in_mode_case = False
mutated_verify["run"] = "\n".join(mutant_lines) + "\n"
Path(sys.argv[4]).write_text(yaml.safe_dump(mutated_apply, sort_keys=False))
mutant_workflow = yaml.safe_load(Path(sys.argv[4]).read_text())
mutant_verify_run = next(
    step["run"]
    for step in mutant_workflow["jobs"]["apply"]["steps"]
    if step.get("name") == "Verify selected image signatures and attestations"
)
try:
    assert_mode_scan_calls(mutant_verify_run)
except SystemExit as exc:
    if "upstream branch" not in str(exc):
        fail(f"public-only scan-call mutant failed for the wrong reason: {exc}")
else:
    fail("public-only scan-call mutant survived upstream validation")
print("PASS: public-only scan-call placement mutant rejected")
print("PASS: scan producer ordering, predicate fields, version pins, and weekly cadence")
PY_SCAN_STRUCTURE

prior_attestation_script="$tmp_dir/prior-attestation-compare.sh"
prior_attestation_mutant="$tmp_dir/prior-attestation-compare-mutant.sh"
# Runtime contract: execute the minimal contiguous sign-images region from
# prior_predicates_file="$(mktemp)" through the rm after its comparison loop.
# That region's only workflow-specific external is stubbed cosign;
# scripts/sbom-canon.sh and jq remain real so the stream decode is exercised.
python3 - "$sign_workflow" "$prior_attestation_script" "$prior_attestation_mutant" <<'PY_EXTRACT_PRIOR_ATTESTATION'
from pathlib import Path
import sys
import textwrap
import yaml


workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
steps = workflow["jobs"]["sign"]["steps"]
runs = [
    step.get("run", "")
    for step in steps
    if step.get("name") == "Generate SBOMs, scan, sign, and attest upstream images"
]
if len(runs) != 1:
    raise SystemExit(f"FAIL: expected one upstream supply-chain run block, found {len(runs)}")
lines = runs[0].splitlines()
start_marker = 'prior_predicates_file="$(mktemp)"'
end_marker = 'rm -f "$prior_predicates_file"'
starts = [index for index, line in enumerate(lines) if line.strip() == start_marker]
if len(starts) != 1:
    raise SystemExit(f"FAIL: expected one prior-attestation region start, found {len(starts)}")
ends = [
    index
    for index, line in enumerate(lines[starts[0] + 1 :], starts[0] + 1)
    if line.strip() == end_marker
]
if len(ends) != 2:
    raise SystemExit(f"FAIL: expected two prior-attestation cleanup lines, found {len(ends)}")
region = textwrap.dedent("\n".join(lines[starts[0] : ends[1] + 1]))
script = (
    "#!/usr/bin/env bash\n"
    "set -euo pipefail\n"
    "run_prior_attestation_compare() {\n"
    + textwrap.indent(region, "  ")
    + "\n}\n"
    "run_prior_attestation_compare\n"
    "printf 'matching_sbom=%s\\n' \"${matching_sbom:-false}\"\n"
)
Path(sys.argv[2]).write_text(script)
slurp_decode = "jq -c -s '.[] | (.payload | @base64d | fromjson | .predicate)'"
non_slurp_decode = "jq -c '(.payload | @base64d | fromjson | .predicate)'"
if script.count(slurp_decode) != 1:
    raise SystemExit("FAIL: prior-attestation decode mutation anchor must occur exactly once")
Path(sys.argv[3]).write_text(script.replace(slurp_decode, non_slurp_decode, 1))
PY_EXTRACT_PRIOR_ATTESTATION

mkdir -p "$tmp_dir/prior-attestation-bin"
cat > "$tmp_dir/prior-attestation-bin/cosign" <<'EOF_PRIOR_COSIGN'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${PRIOR_COSIGN_EXIT:-}" ]; then exit "$PRIOR_COSIGN_EXIT"; fi
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line"
done < "$PRIOR_ATTESTATIONS_FILE"
EOF_PRIOR_COSIGN
chmod +x "$tmp_dir/prior-attestation-bin/cosign"

prior_predicate="$REPO_ROOT/tests/fixtures/sbom/base.spdx.json"
prior_attestations="$tmp_dir/prior-attestations.jsonl"
prior_statement="$(jq -cn --argjson predicate "$(<"$prior_predicate")" '{predicate:$predicate}')"
prior_payload="$(printf '%s' "$prior_statement" | base64 | tr -d '\n')"
# The malformed envelope must come FIRST: streaming jq exits nonzero only when the last value fails, so this ordering is what the non-slurp mutant case relies on to exit 0.
printf '%s\n' '{"payload":"%%%"}' > "$prior_attestations"
jq -cn --arg payload "$prior_payload" '{payload:$payload}' >> "$prior_attestations"
prior_attestations_valid="$tmp_dir/prior-attestations-valid.jsonl"
jq -cn --arg payload "$prior_payload" '{payload:$payload}' > "$prior_attestations_valid"
prior_other_predicate="$REPO_ROOT/tests/fixtures/sbom/same-inventory-different-checksum.spdx.json"
prior_other_statement="$(jq -cn --argjson predicate "$(<"$prior_other_predicate")" '{predicate:$predicate}')"
prior_other_payload="$(printf '%s' "$prior_other_statement" | base64 | tr -d '\n')"
prior_attestations_other="$tmp_dir/prior-attestations-other.jsonl"
jq -cn --arg payload "$prior_other_payload" '{payload:$payload}' > "$prior_attestations_other"
prior_new_canon="$("$REPO_ROOT/scripts/sbom-canon.sh" < "$prior_predicate")"

run_prior_attestation_case() {
  local label="$1"
  local expected_rc="$2"
  local expected_message="$3"
  local script="$4"
  local attestations_file="${5:-$prior_attestations}"
  local cosign_exit="${6:-}"
  local output rc
  set +e
  output="$(
    cd "$REPO_ROOT" &&
      PATH="$tmp_dir/prior-attestation-bin:$PATH" \
      PRIOR_ATTESTATIONS_FILE="$attestations_file" \
      PRIOR_COSIGN_EXIT="$cosign_exit" \
      PUBLIC_KEY="$tmp_dir/test-public-key.pem" \
      image="example.invalid/image" \
      digest="sha256:$(printf 'a%.0s' {1..64})" \
      repository="test/repository" \
      new_canon="$prior_new_canon" \
        bash "$script" 2>&1
  )"
  rc=$?
  set -e
  if [ "$rc" -ne "$expected_rc" ]; then
    echo "sign-images prior-attestation case $label exited $rc, expected $expected_rc: $output" >&2
    exit 1
  fi
  if [ -n "$expected_message" ] && ! grep -Fq "$expected_message" <<< "$output"; then
    echo "sign-images prior-attestation case $label lacked message '$expected_message': $output" >&2
    exit 1
  fi
  echo "PASS: sign-images prior-attestation case $label"
}

run_prior_attestation_case malformed-first 1 "could not decode attestations" \
  "$prior_attestation_script"
run_prior_attestation_case malformed-first-non-slurp-mutant 0 "" \
  "$prior_attestation_mutant"
echo "PASS: sign-images prior-attestation non-slurp mutant killed"
run_prior_attestation_case no-prior 0 "matching_sbom=false" "$prior_attestation_script" "$prior_attestations" 1
run_prior_attestation_case matching-prior 0 "matching_sbom=true" "$prior_attestation_script" "$prior_attestations_valid"
run_prior_attestation_case different-prior 0 "matching_sbom=false" "$prior_attestation_script" "$prior_attestations_other"
echo "PASS: sign-images prior-attestation decode contracts (5 cases)"

scan_verify_script="$tmp_dir/verify-scan-attestation.sh"
scan_verify_mutant="$tmp_dir/verify-scan-attestation-mutant.sh"
python3 - "$apply_workflow" "$scan_verify_script" "$scan_verify_mutant" <<'PY_EXTRACT_SCAN_VERIFY'
from pathlib import Path
import re
import sys
import yaml


workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
steps = workflow["jobs"]["apply"]["steps"]
runs = [
    step.get("run", "")
    for step in steps
    if step.get("name") == "Verify selected image signatures and attestations"
]
if len(runs) != 1:
    raise SystemExit(f"FAIL: expected one image verification run block, found {len(runs)}")
source = runs[0]


def function(name):
    match = re.search(rf"(?ms)^{re.escape(name)}\(\) \{{\n.*?^\}}$", source)
    if match is None:
        raise SystemExit(f"FAIL: could not extract {name} from image verification step")
    return match.group(0)


extracted = function("iso_to_epoch") + "\n" + function("verify_scan_attestation")
script = "#!/usr/bin/env bash\nset -euo pipefail\n" + extracted + '\nverify_scan_attestation test_image "$TEST_IMAGE"\n'
Path(sys.argv[2]).write_text(script)
needle = 'if [ "$age_seconds" -gt "$window_seconds" ]; then'
if script.count(needle) != 1:
    raise SystemExit("FAIL: freshness comparison mutation anchor must occur exactly once")
Path(sys.argv[3]).write_text(script.replace(needle, "if false; then", 1))
PY_EXTRACT_SCAN_VERIFY

mkdir -p "$tmp_dir/scan-bin"
cat > "$tmp_dir/scan-bin/cosign" <<'EOF_SCAN_COSIGN'
#!/usr/bin/env bash
set -euo pipefail
if [ "${SCAN_NO_ATTESTATION:-0}" = 1 ]; then
  exit 1
fi
if [ "${SCAN_MALFORMED_ENVELOPE:-0}" = 1 ]; then
  printf '%s\n' '{"payload":"%%%"}'
  exit 0
fi
while IFS= read -r predicate; do
  statement="$(jq -cn --argjson predicate "$predicate" '{predicate:$predicate}')"
  payload="$(printf '%s' "$statement" | base64 | tr -d '\n')"
  jq -cn --arg payload "$payload" '{payload:$payload}'
done < <(jq -c 'if type == "array" then .[] else . end' "$SCAN_PREDICATE_FILE")
EOF_SCAN_COSIGN
chmod +x "$tmp_dir/scan-bin/cosign" "$scan_verify_script" "$scan_verify_mutant"

scan_digest="sha256:$(printf 'a%.0s' {1..64})"
scan_now_epoch=2000000000
trivy_pin="$("$REPO_ROOT"/scripts/tool-version.sh trivy)"
scan_iso() {
  python3 - "$1" <<'PY_SCAN_ISO'
from datetime import datetime, timezone
import sys
print(datetime.fromtimestamp(int(sys.argv[1]), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY_SCAN_ISO
}

write_scan_predicate() {
  local destination="$1"
  local scanned_at="$2"
  local digest="$3"
  local scanner="$4"
  local version="$5"
  local exit_code="$6"
  local severity="${7:-CRITICAL}"
  jq -cn \
    --arg scanner "$scanner" \
    --arg version "$version" \
    --arg severity "$severity" \
    --arg scanned_at "$scanned_at" \
    --arg digest "$digest" \
    --argjson exit_code "$exit_code" \
    '{scanner:$scanner,trivyVersion:$version,severityGate:$severity,exitCode:$exit_code,scannedAt:$scanned_at,digest:$digest}' \
    > "$destination"
}

run_scan_case() {
  local label="$1"
  local expected_rc="$2"
  local expected_message="$3"
  local script="$4"
  local predicate_file="$5"
  local freshness_days="$6"
  local no_attestation="${7:-0}"
  local malformed_envelope="${8:-0}"
  local output rc
  set +e
  output="$(
    PATH="$tmp_dir/scan-bin:$PATH" \
    PUBLIC_KEY="$tmp_dir/test-public-key.pem" \
    TEST_IMAGE="example.invalid/image@${scan_digest}" \
    TRIVY_VERSION="$trivy_pin" \
    SCAN_FRESHNESS_DAYS="$freshness_days" \
    SCAN_NOW_EPOCH="$scan_now_epoch" \
    SCAN_PREDICATE_FILE="$predicate_file" \
    SCAN_NO_ATTESTATION="$no_attestation" \
    SCAN_MALFORMED_ENVELOPE="$malformed_envelope" \
      bash "$script" 2>&1
  )"
  rc=$?
  set -e
  if [ "$expected_rc" = 0 ] && [ "$rc" -ne 0 ]; then
    echo "scan-attestation case $label unexpectedly failed: $output" >&2
    exit 1
  fi
  if [ "$expected_rc" != 0 ] && [ "$rc" -eq 0 ]; then
    echo "scan-attestation case $label unexpectedly passed" >&2
    exit 1
  fi
  if [ -n "$expected_message" ] && ! grep -Fq "$expected_message" <<< "$output"; then
    echo "scan-attestation case $label lacked message '$expected_message': $output" >&2
    exit 1
  fi
  echo "PASS: scan-attestation case $label"
}

scan_predicate="$tmp_dir/scan-predicate.json"
write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case fresh 0 "" "$scan_verify_script" "$scan_predicate" 10

stale_predicate="$tmp_dir/scan-stale-predicate.json"
fresh_predicate="$tmp_dir/scan-fresh-predicate.json"
write_scan_predicate "$stale_predicate" "$(scan_iso $((scan_now_epoch - 11 * 86400)))" "$scan_digest" trivy "$trivy_pin" 0
write_scan_predicate "$fresh_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 0
jq -s '.' "$stale_predicate" "$fresh_predicate" > "$scan_predicate"
run_scan_case stale-then-fresh 0 "" "$scan_verify_script" "$scan_predicate" 10

stale_scan_time="$(scan_iso $((scan_now_epoch - 11 * 86400)))"
write_scan_predicate "$scan_predicate" "$stale_scan_time" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case stale 1 \
  "scan attestation stale: scannedAt $stale_scan_time older than 10 days for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10
run_scan_case missing 1 "no scan attestation for $scan_digest" "$scan_verify_script" "$scan_predicate" 10 1
run_scan_case malformed-envelope 1 "could not decode attestations" \
  "$scan_verify_script" "$scan_predicate" 10 0 1

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 1
run_scan_case failed-scan 1 \
  "scan attestation reports a failed scan for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

wrong_digest="sha256:$(printf 'b%.0s' {1..64})"
write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$wrong_digest" trivy "$trivy_pin" 0
run_scan_case digest-mismatch 1 "no scan attestation for $scan_digest" "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch + 3600)))" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case future 1 \
  "scan attestation scannedAt is in the future for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" yesterday "$scan_digest" trivy "$trivy_pin" 0
run_scan_case malformed 1 \
  "scan attestation scannedAt is malformed for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 10 * 86400)))" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case boundary 0 "" "$scan_verify_script" "$scan_predicate" 10
past_boundary_scan_time="$(scan_iso $((scan_now_epoch - 10 * 86400 - 1)))"
write_scan_predicate "$scan_predicate" "$past_boundary_scan_time" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case past-boundary 1 \
  "scan attestation stale: scannedAt $past_boundary_scan_time older than 10 days for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case window-60 0 "" "$scan_verify_script" "$scan_predicate" 60
for invalid_window in 0 61 100 999999999999999999999999999999999999 abc 08 07; do
  run_scan_case "window-${invalid_window}" 1 "SCAN_FRESHNESS_DAYS out of range" \
    "$scan_verify_script" "$scan_predicate" "$invalid_window"
done

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 0 CRITICAL,HIGH
run_scan_case severity-critical-high 0 "" "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy "$trivy_pin" 0 HIGH
run_scan_case severity-high 1 \
  "scan attestation severity gate mismatch for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" grype "$trivy_pin" 0
run_scan_case scanner-mismatch 1 \
  "scan attestation scanner or version mismatch for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$(scan_iso $((scan_now_epoch - 3600)))" "$scan_digest" trivy 0.73.0 0
run_scan_case version-mismatch 1 \
  "scan attestation scanner or version mismatch for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10

write_scan_predicate "$scan_predicate" "$stale_scan_time" "$scan_digest" trivy "$trivy_pin" 0
run_scan_case stale-original 1 \
  "scan attestation stale: scannedAt $stale_scan_time older than 10 days for test_image $scan_digest" \
  "$scan_verify_script" "$scan_predicate" 10
run_scan_case stale-mutant 0 "" "$scan_verify_mutant" "$scan_predicate" 10
echo "PASS: scan-attestation freshness mutant killed"
echo "PASS: scan-attestation verification contracts (22 cases)"

# P5-26: fixture hygiene must reject global IPv6 addresses while accepting
# explicit policy markers and non-routable/documentation ranges.
ipv6_global_fixture="$tmp_dir/ipv6-global.json"
ipv6_escaped_fixture="$tmp_dir/ipv6-escaped.json"
ipv6_escaped_key_fixture="$tmp_dir/ipv6-escaped-key.json"
ipv6_allowed_fixture="$tmp_dir/ipv6-allowed.json"
ipv6_digest_fixture="$tmp_dir/ipv6-digest.json"
printf '%s\n' '{"value":"2001:4860:4860::8888"}' > "$ipv6_global_fixture"
printf '%s\n' '{"value":"2001\u003a4860\u003a4860\u003a\u003a8888"}' > "$ipv6_escaped_fixture"
printf '%s\n' '{"2001\u003a4860\u003a4860\u003a\u003a8888":"value"}' > "$ipv6_escaped_key_fixture"
printf '%s\n' '{"values":["::/0","::1","fe80::1","fd00::1","2001:db8::1","::"]}' > "$ipv6_allowed_fixture"
printf '%s\n' '{"digest":"01234567:89abcdef:01234567:89abcdef:01234567:89abcdef:01234567:89abcdef"}' > "$ipv6_digest_fixture"
set +e
ipv6_global_output="$(bash "$REPO_ROOT/scripts/fixture-hygiene.sh" "$ipv6_global_fixture" 2>&1)"
ipv6_global_rc=$?
set -e
if [ "$ipv6_global_rc" -ne 1 ] || \
   ! grep -Fq 'contains non-private IPv6 literal 2001:4860:4860::8888' <<< "$ipv6_global_output"; then
  echo "fixture hygiene must reject a globally routable IPv6 literal: $ipv6_global_output" >&2
  exit 1
fi
set +e
ipv6_escaped_output="$(bash "$REPO_ROOT/scripts/fixture-hygiene.sh" "$ipv6_escaped_fixture" 2>&1)"
ipv6_escaped_rc=$?
set -e
if [ "$ipv6_escaped_rc" -ne 1 ] || \
   ! grep -Fq 'contains non-private IPv6 literal 2001:4860:4860::8888' <<< "$ipv6_escaped_output"; then
  echo "fixture hygiene must reject a Unicode-escaped global IPv6 literal: $ipv6_escaped_output" >&2
  exit 1
fi
set +e
ipv6_escaped_key_output="$(bash "$REPO_ROOT/scripts/fixture-hygiene.sh" "$ipv6_escaped_key_fixture" 2>&1)"
ipv6_escaped_key_rc=$?
set -e
if [ "$ipv6_escaped_key_rc" -ne 1 ] || \
   ! grep -Fq 'contains non-private IPv6 literal 2001:4860:4860::8888' <<< "$ipv6_escaped_key_output"; then
  echo "fixture hygiene must reject a Unicode-escaped global IPv6 key: $ipv6_escaped_key_output" >&2
  exit 1
fi
for accepted_fixture in "$ipv6_allowed_fixture" "$ipv6_digest_fixture"; do
  if ! accepted_output="$(bash "$REPO_ROOT/scripts/fixture-hygiene.sh" "$accepted_fixture" 2>&1)"; then
    echo "fixture hygiene rejected an allowed IPv6 or digest case: $accepted_output" >&2
    exit 1
  fi
done
echo "PASS: fixture IPv6 hygiene contracts (5 cases)"

# P5-31: the periodic/main plan-mode workflow must keep the LocalStack action
# and image pins byte-equal to the owner-PR job and produce bootstrap state
# before invoking the Makefile-owned IAM matrix plan path.
if [ ! -f "$iam_matrix_workflow" ]; then
  echo "iam-matrix-plan workflow is missing" >&2
  exit 1
fi
python3 - "$iam_matrix_workflow" "$plan_workflow" <<'PY_IAM_MATRIX_WORKFLOW'
from pathlib import Path
import sys
import yaml


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_workflow(path, label):
    try:
        workflow = yaml.safe_load(Path(path).read_text())
    except (OSError, yaml.YAMLError):
        fail(f"{label} workflow could not be loaded as YAML")
    if not isinstance(workflow, dict):
        fail(f"{label} workflow must be a YAML mapping")
    return workflow


def matching_indices(steps, predicate):
    return [index for index, step in enumerate(steps) if predicate(step)]


def step_string(step, key):
    value = step.get(key, "") if isinstance(step, dict) else ""
    return value if isinstance(value, str) else ""


iam_matrix = load_workflow(sys.argv[1], "iam-matrix-plan")
plan = load_workflow(sys.argv[2], "terraform-plan")

jobs = iam_matrix.get("jobs")
if not isinstance(jobs, dict) or len(jobs) != 1:
    fail("iam-matrix-plan must contain exactly one job")
iam_job = next(iter(jobs.values()))
if not isinstance(iam_job, dict):
    fail("iam-matrix-plan job must be a mapping")
iam_steps = iam_job.get("steps")
if not isinstance(iam_steps, list) or not all(
    isinstance(step, dict) for step in iam_steps
):
    fail("iam-matrix-plan job steps must be a list of mappings")

plan_jobs = plan.get("jobs")
plan_job = plan_jobs.get("plan-localstack") if isinstance(plan_jobs, dict) else None
plan_steps = plan_job.get("steps") if isinstance(plan_job, dict) else None
if not isinstance(plan_steps, list) or not all(
    isinstance(step, dict) for step in plan_steps
):
    fail("terraform-plan plan-localstack steps must be a list of mappings")

localstack_prefix = "LocalStack/setup-localstack@"
iam_localstack = matching_indices(
    iam_steps,
    lambda step: step_string(step, "uses").startswith(localstack_prefix),
)
plan_localstack = matching_indices(
    plan_steps,
    lambda step: step_string(step, "uses").startswith(localstack_prefix),
)
if len(iam_localstack) != 1:
    fail("iam-matrix-plan must contain exactly one LocalStack action ref and image-tag")
if len(plan_localstack) != 1:
    fail("terraform-plan plan-localstack job must contain exactly one LocalStack action")
iam_localstack_step = iam_steps[iam_localstack[0]]
plan_localstack_step = plan_steps[plan_localstack[0]]
iam_with = iam_localstack_step.get("with")
plan_with = plan_localstack_step.get("with")
if not isinstance(iam_with, dict) or not isinstance(plan_with, dict):
    fail("LocalStack workflow steps must carry with mappings")
plan_localstack_ref = step_string(plan_localstack_step, "uses")
plan_localstack_tag = plan_with.get("image-tag")
if step_string(iam_localstack_step, "uses") != plan_localstack_ref:
    fail("iam-matrix-plan LocalStack action ref must equal terraform-plan.yml")
if (
    not isinstance(plan_localstack_tag, str)
    or not plan_localstack_tag
    or iam_with.get("image-tag") != plan_localstack_tag
):
    fail("iam-matrix-plan LocalStack image-tag must equal terraform-plan.yml")
print("PASS: iam-matrix-plan workflow LocalStack pin cardinality")

forbidden_commands = (
    "scripts/iam-matrix-inventory.sh",
    "tests/iam-matrix-contracts.sh",
    "bootstrap/policy-size-check.sh",
)
if any(
    command in step_string(step, "run")
    for step in iam_steps
    for command in forbidden_commands
):
    fail(
        "iam-matrix-plan workflow must use the Makefile target instead of "
        "direct inventory, contract, or render scripts"
    )
bootstrap_indices = matching_indices(
    iam_steps,
    lambda step: "make bootstrap-apply TARGET=localstack"
    in step_string(step, "run"),
)
matrix_indices = matching_indices(
    iam_steps,
    lambda step: "make iam-matrix-plan" in step_string(step, "run"),
)
if len(bootstrap_indices) != 1 or len(matrix_indices) != 1:
    fail(
        "iam-matrix-plan must contain exactly one bootstrap apply and IAM "
        "matrix plan invocation"
    )
if bootstrap_indices[0] >= matrix_indices[0]:
    fail("iam-matrix-plan must apply the LocalStack bootstrap before make iam-matrix-plan")
print("PASS: iam-matrix-plan workflow producer/consumer cardinality and ordering")

if iam_job.get("if") != "github.ref == 'refs/heads/main'":
    fail("iam-matrix-plan job must be gated on refs/heads/main")
permissions = iam_matrix.get("permissions")
if not isinstance(permissions, dict) or permissions.get("contents") != "read":
    fail("iam-matrix-plan workflow must declare a top-level permissions: contents: read")
checkout_indices = matching_indices(
    iam_steps,
    lambda step: step_string(step, "uses").startswith("actions/checkout@"),
)
if len(checkout_indices) != 1:
    fail("iam-matrix-plan must contain exactly one checkout step")
checkout_with = iam_steps[checkout_indices[0]].get("with")
if not isinstance(checkout_with, dict) or checkout_with.get("persist-credentials") is not False:
    fail("iam-matrix-plan checkout step must set persist-credentials: false")
print("PASS: iam-matrix-plan workflow contracts")
PY_IAM_MATRIX_WORKFLOW
python3 - "$sweeper_workflow" "$plan_workflow" "$REPO_ROOT/scripts/sweep.sh" <<'PY'
from pathlib import Path
import re
import sys
import yaml


def one_index(steps, predicate, label):
    matches = [index for index, step in enumerate(steps) if predicate(step)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {label}, found {len(matches)}")
    return matches[0]


sweeper = yaml.safe_load(Path(sys.argv[1]).read_text())
sweep_job = sweeper["jobs"]["sweep"]
sweep_steps = sweep_job["steps"]
timeout_minutes = sweep_job["timeout-minutes"]
constant_match = re.search(
    r'^STAGE2_CLAIM_STALE_SECONDS="?([0-9]+)"?$',
    Path(sys.argv[3]).read_text(),
    re.MULTILINE,
)
if constant_match is None:
    raise SystemExit("sweep.sh must declare STAGE2_CLAIM_STALE_SECONDS")
if int(constant_match.group(1)) != 2 * timeout_minutes * 60:
    raise SystemExit("Stage-2 stale-claim threshold must equal twice the sweeper timeout")
setup_index = one_index(
    sweep_steps,
    lambda step: step.get("uses") == "hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e",
    "pinned Terraform setup in sweeper sweep job",
)
backend_index = one_index(
    sweep_steps,
    lambda step: step.get("run") == "scripts/write-preview-backend.sh",
    "AWS backend writer in sweeper sweep job",
)
sweep_index = one_index(
    sweep_steps,
    lambda step: 'scripts/sweep.sh env "$ENV_ID"' in step.get("run", ""),
    "environment sweep in sweeper sweep job",
)
if not setup_index < sweep_index or not backend_index < sweep_index:
    raise SystemExit("sweeper must set up Terraform and write the AWS backend before sweeping an environment")

plan = yaml.safe_load(Path(sys.argv[2]).read_text())
plan_steps = plan["jobs"]["plan-localstack"]["steps"]
bootstrap_index = one_index(
    plan_steps,
    lambda step: step.get("run") == "make bootstrap-apply TARGET=localstack",
    "LocalStack bootstrap apply in terraform-plan plan-localstack job",
)
plan_index = one_index(
    plan_steps,
    lambda step: "make plan TARGET=localstack" in step.get("run", ""),
    "LocalStack Terraform plan in terraform-plan plan-localstack job",
)
if not bootstrap_index < plan_index:
    raise SystemExit("terraform-plan must bootstrap LocalStack state before planning")
PY
workflow_sweep_call="$(grep -F \
  "SWEEP_IN_JOB=true scripts/sweep.sh env \"\$ENV_ID\"" \
  "$apply_workflow" || true)"
workflow_sweep_expected="            if ! SWEEP_IN_JOB=true scripts/sweep.sh env \"\$ENV_ID\"; then"
if [ "$workflow_sweep_call" != "$workflow_sweep_expected" ]; then
  echo 'session-apply sweep.sh env call must remain byte-identical' >&2
  exit 1
fi
echo 'PASS: session-apply sweep.sh env call remains byte-identical'

validate_guard="$(sed -n '/^  validate-input:/,/^  apply:/s/^    if: //p' "$apply_workflow")"
apply_guard="$(sed -n '/^  apply:/,/^    runs-on:/s/^    if: //p' "$apply_workflow")"
setup_localstack_guard="$(sed -n '/      - name: Start LocalStack/,/        uses:/s/^        if: //p' "$apply_workflow")"
for guard_record in \
  "validate-input job|$validate_guard" \
  "apply job|$apply_guard" \
  "setup-localstack step|$setup_localstack_guard"; do
  guard_label="${guard_record%%|*}"
  guard="${guard_record#*|}"
  for required_owner_check in \
    'github.actor == github.repository_owner' \
    'github.triggering_actor == github.repository_owner'; do
    if [[ "$guard" != *"$required_owner_check"* ]]; then
      echo "session-apply $guard_label LocalStack guard must include: $required_owner_check" >&2
      exit 1
    fi
  done
done

bash "$REPO_ROOT/tests/localstack-concurrency-signal.sh"

# tools.lock lists each tool twice (version and checksum sections); every
# workflow version read must go through scripts/tool-version.sh, which prints
# exactly one semantic version (a multi-line value is an invalid GITHUB_OUTPUT
# record and broke the PR plan lane on PR #5).
if grep -rnE "(grep|awk)[^\n]*tools\.lock" "$REPO_ROOT/.github/workflows" >/dev/null; then
  echo "workflows must read tool versions through scripts/tool-version.sh, never grep or awk on tools.lock" >&2
  exit 1
fi
for tool in terraform tflint checkov cosign syft trivy; do
  version_lines="$("$REPO_ROOT/scripts/tool-version.sh" "$tool" | wc -l | tr -d ' ')"
  if [ "$version_lines" != 1 ]; then
    echo "scripts/tool-version.sh $tool must print exactly one line, printed $version_lines" >&2
    exit 1
  fi
done
if "$REPO_ROOT/scripts/tool-version.sh" no-such-tool >/dev/null 2>&1; then
  echo "scripts/tool-version.sh must fail for an unknown tool" >&2
  exit 1
fi

bash "$REPO_ROOT/tests/policy-size-contracts.sh"
bash "$REPO_ROOT/tests/iam-matrix-contracts.sh"
bash "$REPO_ROOT/tests/demo-contracts.sh"

# tests/dispatch-ordering.sh derives run order from job timestamps only:
# GitHub stamps run_started_at at dispatch acceptance, before the concurrency
# group releases a held run (observed live 2026-09-03).
ordering_script="$REPO_ROOT/tests/dispatch-ordering.sh"
if [ ! -f "$ordering_script" ]; then
  echo "tests/dispatch-ordering.sh is missing; the ordering-source contract cannot run" >&2
  exit 1
fi
# Backslash-continued lines are joined so a jq call split across lines is
# inspected as one; quotes around the jq filter are optional. Any jq read of
# the run-level fields is forbidden except the audit capture line.
ordering_joined="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$ordering_script")"
forbidden_reads="$(grep -nE "(jq|--jq)[^#]*['\"]?[^'\"]*\.(run_started_at|updated_at)([^A-Za-z0-9_]|$)" <<< "$ordering_joined" \
  | grep -vE "run_started_at:\.run_started_at,updated_at:\.updated_at" || true)"
if [ -n "$forbidden_reads" ]; then
  echo "dispatch-ordering.sh must compare job timestamps, never read run_started_at or updated_at for ordering:" >&2
  echo "$forbidden_reads" >&2
  exit 1
fi
# Each comparison function must itself read both job-derived fields via jq.
for fn in assert_terminal_before_start verify_aws_final_cleanup; do
  fn_body="$(sed -n "/^${fn}() {/,/^}/p" <<< "$ordering_joined")"
  if [ -z "$fn_body" ]; then
    echo "dispatch-ordering.sh must define ${fn}() at column 0 (contract extraction found nothing)" >&2
    exit 1
  fi
  for field in jobs_completed_at jobs_started_at; do
    if ! grep -Eq "jq -r ['\"]?\.${field}([^A-Za-z0-9_]|$)" <<< "$fn_body"; then
      echo "dispatch-ordering.sh ${fn}() must read .$field via jq -r" >&2
      exit 1
    fi
  done
done
bash "$REPO_ROOT/tests/dispatch-ordering-contracts.sh"

# GitHub reports a concurrency-held run as pending; both pending and queued
# must be accepted inside each function, whether in one case arm or two.
for fn in assert_three_queued_polls assert_run_queued; do
  fn_body="$(sed -n "/^${fn}() {/,/^}/p" <<< "$ordering_joined")"
  if [ -z "$fn_body" ]; then
    echo "dispatch-ordering.sh must define ${fn}() at column 0 (contract extraction found nothing)" >&2
    exit 1
  fi
  for held in pending queued; do
    if ! grep -Eq "(^|[^A-Za-z0-9_])${held}(\)|\|)" <<< "$fn_body"; then
      echo "dispatch-ordering.sh ${fn}() must treat GitHub's ${held} status as a held run" >&2
      exit 1
    fi
  done
done

# Execute both close workflow blocks against controlled lease/close/sweep
# scripts so their generation, status, and owner forwarding are checked as
# behavior rather than by grepping the workflow source.
workflow_exec_root="$tmp_dir/workflow-close"
workflow_aws_run_block="$workflow_exec_root/aws-run.sh"
workflow_localstack_run_block="$workflow_exec_root/localstack-run.sh"
mkdir -p "$workflow_exec_root/scripts"
python3 - "$apply_workflow" "$workflow_aws_run_block" "$workflow_localstack_run_block" <<'PY'
from pathlib import Path
import sys
import yaml

workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
steps = workflow["jobs"]["apply"]["steps"]
for name, destination in (
    ("Close AWS on failure or cancellation (stage 1)", sys.argv[2]),
    ("Close and sweep LocalStack after acceptance or failure", sys.argv[3]),
):
    matches = [step["run"] for step in steps if step.get("name") == name]
    if len(matches) != 1:
        raise SystemExit(f"expected one {name!r} step, found {len(matches)}")
    Path(destination).write_text(matches[0])
PY
if grep -Fq 'seq ' "$workflow_localstack_run_block"; then
  echo "session-apply LocalStack sweep loop must not depend on an external seq command" >&2
  exit 1
fi
if [ "$(grep -Fc 'sweep_closed' "$workflow_localstack_run_block")" -lt 2 ]; then
  echo "session-apply LocalStack sweep loop must set sweep_closed before and check it after the loop" >&2
  exit 1
fi
echo "PASS: session-apply LocalStack sweep loop is a bounded C-style loop guarded by sweep_closed"

cat > "$workflow_exec_root/scripts/lease.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = get ]
lease_calls=1
if [ -f "$WORKFLOW_LEASE_CALLS" ]; then
  lease_calls=$(( $(cat "$WORKFLOW_LEASE_CALLS") + 1 ))
fi
printf '%s\n' "$lease_calls" > "$WORKFLOW_LEASE_CALLS"
if [ "$lease_calls" -eq 1 ]; then
  printf '%s\n' '{"status":"open","generation":7,"owner":"workflow-run-1"}'
  exit 0
fi
case "$WORKFLOW_SWEEP_SCENARIO" in
  closes-after-three)
    sweep_calls="$(cat "$WORKFLOW_SWEEP_CALLS")"
    if [ "$sweep_calls" -ge 3 ]; then
      status=closed
    else
      status=closing
    fi
    ;;
  closing-forever) status=closing ;;
  unexpected-status) status=cleanup_failed ;;
  sweep-fails) status=closing ;;
  *) echo "unexpected workflow scenario" >&2; exit 2 ;;
esac
jq -cn --arg status "$status" '{status:$status,generation:7,owner:"workflow-run-1"}'
EOF
cat > "$workflow_exec_root/scripts/close-env.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$WORKFLOW_CLOSE_ARGS_LOG"
EOF
cat > "$workflow_exec_root/scripts/sweep.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$WORKFLOW_SWEEP_ARGS_LOG"
sweep_calls=1
if [ -f "$WORKFLOW_SWEEP_CALLS" ]; then
  sweep_calls=$(( $(cat "$WORKFLOW_SWEEP_CALLS") + 1 ))
fi
printf '%s\n' "$sweep_calls" > "$WORKFLOW_SWEEP_CALLS"
if [ "$WORKFLOW_SWEEP_SCENARIO" = sweep-fails ]; then
  exit 1
fi
EOF
chmod +x "$workflow_exec_root/scripts/lease.sh" \
  "$workflow_exec_root/scripts/close-env.sh" "$workflow_exec_root/scripts/sweep.sh"
(
  cd "$workflow_exec_root"
  ENV_ID=contract \
  GITHUB_RUN_ID=workflow-run \
  GITHUB_RUN_ATTEMPT=1 \
  WORKFLOW_LEASE_CALLS="$workflow_exec_root/aws-lease-calls" \
  WORKFLOW_CLOSE_ARGS_LOG="$workflow_exec_root/aws-close-args.log" \
  WORKFLOW_SWEEP_CALLS="$workflow_exec_root/aws-sweep-calls" \
  WORKFLOW_SWEEP_SCENARIO=closes-after-three \
    bash "$workflow_aws_run_block"
)
if [ "$(cat "$workflow_exec_root/aws-close-args.log")" != \
     "--generation 7 --from open --owner workflow-run-1 contract" ]; then
  echo "session-apply AWS close must forward its observed generation, status, and owner" >&2
  exit 1
fi
run_localstack_workflow_case() {
  local scenario="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  : > "$workflow_exec_root/sweep-args.log"
  rm -f "$workflow_exec_root/lease-calls" "$workflow_exec_root/sweep-calls"
  set +e
  (
    cd "$workflow_exec_root"
    ENV_ID=contract \
    GITHUB_RUN_ID=workflow-run \
    GITHUB_RUN_ATTEMPT=1 \
    SWEEP_LOOP_SLEEP_SECONDS=0 \
    WORKFLOW_CLOSE_ARGS_LOG="$workflow_exec_root/close-args.log" \
    WORKFLOW_LEASE_CALLS="$workflow_exec_root/lease-calls" \
    WORKFLOW_SWEEP_ARGS_LOG="$workflow_exec_root/sweep-args.log" \
    WORKFLOW_SWEEP_CALLS="$workflow_exec_root/sweep-calls" \
    WORKFLOW_SWEEP_SCENARIO="$scenario" \
      bash "$workflow_localstack_run_block"
  ) >"$stdout_file" 2>"$stderr_file"
  workflow_case_rc=$?
  set -e
}

run_localstack_workflow_case closes-after-three \
  "$workflow_exec_root/closes.stdout" "$workflow_exec_root/closes.stderr"
if [ "$workflow_case_rc" -ne 0 ] || [ "$(cat "$workflow_exec_root/sweep-calls")" -ne 3 ]; then
  echo "session-apply LocalStack sweep must stop after the lease closes on attempt three" >&2
  exit 1
fi
if [ "$(cat "$workflow_exec_root/close-args.log")" != \
     "--generation 7 --from open --owner workflow-run-1 contract" ]; then
  echo "session-apply LocalStack close must forward its observed generation, status, and owner" >&2
  exit 1
fi
if [ "$(sort -u "$workflow_exec_root/sweep-args.log")" != "env contract" ]; then
  echo "session-apply LocalStack close must invoke its in-job sweep" >&2
  exit 1
fi

run_localstack_workflow_case closing-forever \
  "$workflow_exec_root/closing.stdout" "$workflow_exec_root/closing.stderr"
if [ "$workflow_case_rc" -eq 0 ] || [ "$(cat "$workflow_exec_root/sweep-calls")" -ne 20 ] || \
   ! grep -Fq 'still closing after 20 in-job sweep attempts; state versions may remain' \
     "$workflow_exec_root/closing.stderr"; then
  echo "session-apply LocalStack sweep must fail after twenty closing results" >&2
  exit 1
fi

run_localstack_workflow_case unexpected-status \
  "$workflow_exec_root/unexpected.stdout" "$workflow_exec_root/unexpected.stderr"
if [ "$workflow_case_rc" -eq 0 ] || [ "$(cat "$workflow_exec_root/sweep-calls")" -ne 1 ] || \
   ! grep -Fq "unexpected lease status 'cleanup_failed'" "$workflow_exec_root/unexpected.stderr"; then
  echo "session-apply LocalStack sweep must fail on the first unexpected lease status" >&2
  exit 1
fi

run_localstack_workflow_case sweep-fails \
  "$workflow_exec_root/sweep-fails.stdout" "$workflow_exec_root/sweep-fails.stderr"
if [ "$workflow_case_rc" -eq 0 ] || [ "$(cat "$workflow_exec_root/sweep-calls")" -ne 1 ] || \
   ! grep -Fq 'in-job LocalStack sweep failed' "$workflow_exec_root/sweep-fails.stderr"; then
  echo "session-apply LocalStack sweep must fail immediately on a sweep error" >&2
  exit 1
fi
echo "PASS: session-apply bounded LocalStack sweep loop (4 cases)"

# P5-3: Conftest is checksum-pinned in both PR jobs and in session apply;
# each rendered plan is gated before its consumer can apply or report success.
python3 - "$plan_workflow" "$apply_workflow" <<'PY_CONFTST'
from pathlib import Path
import sys
import yaml


def one_index(steps, predicate, label):
    matches = [index for index, step in enumerate(steps) if predicate(step)]
    if len(matches) != 1:
        raise SystemExit(f"expected one {label}, found {len(matches)}")
    return matches[0]


def assert_conftest_install(steps, job_label):
    version_index = one_index(
        steps,
        lambda step: step.get("name") == "Read conftest version from tools.lock"
        and "scripts/tool-version.sh conftest" in step.get("run", ""),
        f"conftest version read in {job_label}",
    )
    install_index = one_index(
        steps,
        lambda step: step.get("name") == "Install conftest",
        f"conftest install in {job_label}",
    )
    install_run = steps[install_index].get("run", "")
    for required in (
        "scripts/tool-ci-digest.sh conftest",
        "sha256sum",
        "conftest_${version}_Linux_x86_64.tar.gz",
        'if [ "$actual" != "$expected" ]',
        "sudo install -m 0755 conftest /usr/local/bin/conftest",
        "conftest --version",
    ):
        if required not in install_run:
            raise SystemExit(f"{job_label} conftest install is missing {required!r}")
    if not version_index < install_index:
        raise SystemExit(f"{job_label} must read the conftest version before installing it")
    return install_index


plan = yaml.safe_load(Path(sys.argv[1]).read_text())
gates_steps = plan["jobs"]["gates"]["steps"]
gates_install_index = assert_conftest_install(gates_steps, "terraform-plan gates job")
pyyaml_install_index = one_index(
    gates_steps,
    lambda step: step.get("name") == "Install PyYAML"
    and step.get("run") == "pip install pyyaml==$(scripts/tool-version.sh pyyaml)",
    "PyYAML install in terraform-plan gates job",
)
run_gates_index = one_index(
    gates_steps,
    lambda step: step.get("name") == "Run gates",
    "Run gates in terraform-plan gates job",
)
if not gates_install_index < pyyaml_install_index < run_gates_index:
    raise SystemExit("terraform-plan gates job must install Conftest and pinned PyYAML before Run gates")

plan_steps = plan["jobs"]["plan-localstack"]["steps"]
plan_install_index = assert_conftest_install(plan_steps, "terraform-plan plan-localstack job")
bootstrap_gate_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Conftest policy gate on the bootstrap plan",
    "bootstrap Conftest policy gate in terraform-plan plan-localstack job",
)
bootstrap_gate = plan_steps[bootstrap_gate_index]
bootstrap_gate_run = bootstrap_gate.get("run", "")
for required in (
    "cp bootstrap/localstack.backend_override.tf.example bootstrap/backend_override.tf",
    "env -u AWS_PROFILE -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN terraform -chdir=bootstrap init -reconfigure -input=false",
    'env -u AWS_PROFILE -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN terraform -chdir=bootstrap plan -input=false -out=/tmp/bootstrap.tfplan -var "target=localstack" -var budget_email=unused',
    "env -u AWS_PROFILE -u AWS_SESSION_TOKEN -u AWS_SECURITY_TOKEN terraform -chdir=bootstrap show -json /tmp/bootstrap.tfplan > /tmp/bootstrap-plan.json",
    "conftest test --policy policy/ /tmp/bootstrap-plan.json",
    "rm -f bootstrap/backend_override.tf /tmp/bootstrap.tfplan",
    "trap cleanup EXIT",
):
    if required not in bootstrap_gate_run:
        raise SystemExit(f"bootstrap Conftest gate is missing {required!r}")
for key, value in {
    "AWS_ENDPOINT_URL": "http://localhost:4566",
    "AWS_ACCESS_KEY_ID": "test",
    "AWS_SECRET_ACCESS_KEY": "test",
    "AWS_DEFAULT_REGION": "us-east-1",
    "AWS_EC2_METADATA_DISABLED": "true",
    "TF_DATA_DIR": ".terraform-localstack",
}.items():
    if str(bootstrap_gate.get("env", {}).get(key, "")).lower() != value:
        raise SystemExit(f"bootstrap Conftest gate env {key} must be {value}")
bootstrap_apply_index = one_index(
    plan_steps,
    lambda step: step.get("run") == "make bootstrap-apply TARGET=localstack",
    "LocalStack bootstrap apply in terraform-plan plan-localstack job",
)
policy_size_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Check bootstrap IAM policy sizes"
    and step.get("run") == "bootstrap/policy-size-check.sh"
    and step.get("env", {}).get("POLICY_SIZE_PLAN_JSON_OUT") == "/tmp/bootstrap-plan-post-apply.json",
    "post-apply bootstrap IAM policy-size render in terraform-plan plan-localstack job",
)
iam_matrix_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Check IAM matrix against post-apply plan"
    and step.get("run") == "bash tests/iam-matrix-contracts.sh /tmp/bootstrap-plan-post-apply.json",
    "post-apply IAM matrix contract in terraform-plan plan-localstack job",
)
terraform_plan_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Terraform plan (LocalStack)",
    "Terraform plan in terraform-plan plan-localstack job",
)
summary_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Redacted plan summary",
    "redacted plan summary in terraform-plan plan-localstack job",
)
conftest_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Conftest policy gate on the LocalStack plan"
    and step.get("run") == "conftest test --policy policy/ /tmp/plan.json",
    "LocalStack Conftest policy gate in terraform-plan plan-localstack job",
)
comment_index = one_index(
    plan_steps,
    lambda step: step.get("name") == "Post or update PR plan comment",
    "PR plan comment in terraform-plan plan-localstack job",
)
if not (
    plan_install_index
    < bootstrap_gate_index
    < bootstrap_apply_index
    < policy_size_index
    < iam_matrix_index
    < terraform_plan_index
    < summary_index
    < conftest_index
    < comment_index
):
    raise SystemExit(
        "terraform-plan must install Conftest, gate bootstrap, apply bootstrap, render and gate the IAM matrix, plan, summarize, gate the live plan, then comment in that order"
    )

apply = yaml.safe_load(Path(sys.argv[2]).read_text())
apply_steps = apply["jobs"]["apply"]["steps"]
apply_install_index = assert_conftest_install(apply_steps, "session-apply apply job")
saved_plan_index = one_index(
    apply_steps,
    lambda step: step.get("name") == "Terraform plan (AWS)",
    "saved AWS plan in session-apply apply job",
)
saved_plan_gate_index = one_index(
    apply_steps,
    lambda step: step.get("name") == "Conftest policy gate on the saved plan"
    and "terraform -chdir=envs/preview show -json tfplan.bin" in step.get("run", "")
    and "conftest test --policy policy/" in step.get("run", ""),
    "saved-plan Conftest policy gate in session-apply apply job",
)
apply_index = one_index(
    apply_steps,
    lambda step: step.get("name") == "Terraform apply"
    and "make apply" in step.get("run", ""),
    "Terraform apply in session-apply apply job",
)
if not apply_install_index < saved_plan_index < saved_plan_gate_index < apply_index:
    raise SystemExit("session-apply must install Conftest and gate the saved Terraform plan before make apply")
PY_CONFTST

grep -Fqx 'run_gate conftest' "$REPO_ROOT/scripts/gates.sh" || {
  echo "scripts/gates.sh must run the conftest gate" >&2
  exit 1
}
for required_lock_line in \
  'conftest 0.69.0' \
  'conftest f41dbda68a6932878f6b26a976256eb415b179f552fd81e10966b0ee39c1bb9f' \
  'conftest 96fc2fbf11f0afde51256647127e6f00a64ce839a4d9a0a1aef2426c0e6f4b3f'; do
  grep -Fqx "$required_lock_line" "$REPO_ROOT/tools.lock" || {
    echo "tools.lock is missing: $required_lock_line" >&2
    exit 1
  }
done

echo "PASS: phase3 shell contracts"
