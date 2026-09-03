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
if ! grep -Fq "if: always() && (failure() || cancelled()) && steps.lease-open.outputs.acquired == 'true' && inputs.target == 'aws'" \
    "$REPO_ROOT/.github/workflows/session-apply.yml"; then
  echo "session-apply must run the AWS stage-1 close on failure or cancellation once the lease is acquired" >&2
  exit 1
fi

apply_workflow="$REPO_ROOT/.github/workflows/session-apply.yml"
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

echo "PASS: phase3 shell contracts"
