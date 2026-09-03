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

echo "PASS: phase3 shell contracts"
