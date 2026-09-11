#!/usr/bin/env bash
# shellcheck disable=SC2154 # Globals are provided by the sourcing contract suite.

# Phase-2 IAM simulator contracts. This file is sourced by
# tests/iam-simulate-contracts.sh so it shares that suite's result counters and
# temporary directory.

IAM_SIM_RUNNER="$REPO_ROOT/scripts/iam-simulate.sh"
IAM_SIM_ROLE_LANE="$REPO_ROOT/scripts/iam-simulate-roles.sh"
IAM_SIM_CORE="$REPO_ROOT/scripts/iam_simulate_core.py"
IAM_SIM_FIXTURE_FACTORY="$REPO_ROOT/tests/lib/iam-simulate-fixtures.py"
IAM_SIM_AWS_WRAPPER="$REPO_ROOT/scripts/aws-cli.sh"
IAM_SIM_REPORT_RENDERER="$REPO_ROOT/scripts/iam-simulate-report.sh"
IAM_SIM_ARTIFACT_HYGIENE="$REPO_ROOT/scripts/artifact-hygiene.sh"
IAM_SIM_REPORT_FIXTURES="$REPO_ROOT/tests/fixtures/artifact-hygiene"

phase2_setup() {
  phase2_dir="$tmp_dir/phase2"
  phase2_plan="$phase2_dir/plan.json"
  phase2_fake_aws="$phase2_dir/bin/aws"
  phase2_calls="$phase2_dir/calls"
  phase2_roles="$phase2_dir/roles"
  mkdir -p "$phase2_dir/bin" "$phase2_calls" "$phase2_roles"

  python3 "$IAM_SIM_FIXTURE_FACTORY" build "$TAXONOMY" "$phase2_dir" \
    "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
  phase2_authorization_core_mutant="$phase2_dir/iam-simulate-core-authorization-groups-mutant.py"
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-core-authorization-groups \
    "$IAM_SIM_CORE" "$phase2_authorization_core_mutant"

  # The fake is the only executable named aws in these contracts. Every call
  # still traverses scripts/aws-cli.sh; behavior is data-driven by the factory.
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'exec python3 "'"$IAM_SIM_FIXTURE_FACTORY"'" fake-aws "'"$phase2_dir/role-scenarios.json"'" "$@"' \
    >"$phase2_fake_aws"
  chmod +x "$phase2_fake_aws"
}

reset_phase2_fake() {
  rm -f "$phase2_calls"/* "$phase2_roles"/*
}

phase2_call_count() {
  local service=$1
  local operation=$2
  python3 - "$phase2_calls" "$service" "$operation" <<'PY'
import json
from pathlib import Path
import sys
count = 0
for path in Path(sys.argv[1]).glob("*.json"):
    args = json.loads(path.read_text(encoding="utf-8"))
    count += args[:2] == sys.argv[2:4]
print(count)
PY
}

assert_submitted_document_equals_plan() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" assert-submitted-document-equals-plan "$@"
}

mutate_submitted_document() {
  local submode=$1 option
  shift
  case "$submode" in
    policy-input-list) option=--policy-input-list ;;
    permissions-boundary-policy-input-list) option=--permissions-boundary-policy-input-list ;;
    *) echo "FAIL: unknown submitted-document mutation: $submode" >&2; return 1 ;;
  esac
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-submitted-document "$@" "$option"
}

run_phase2_runner() {
  local scenario=$1
  local response=$2
  local vectors=$3
  local report=$4
  local expected_inputs="$phase2_dir/expected-custom-inputs.json"
  local test_runner="${IAM_SIM_TEST_RUNNER:-$IAM_SIM_RUNNER}"
  shift 4
  python3 - "$vectors" "$expected_inputs" "$@" <<'PY'
import json
from pathlib import Path
import sys

vector_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
remaining = sys.argv[3:]
only = remaining[remaining.index("--only") + 1] if "--only" in remaining else None
vectors = [
    {
        "schema_version": envelope["schema_version"],
        "document": envelope["document"],
        "sid": envelope["sid"],
        **case,
    }
    for path in sorted(vector_dir.rglob("*.json"))
    for envelope in [json.loads(path.read_text(encoding="utf-8"))]
    for case in envelope["cases"]
]
if only is not None:
    vectors = [vector for vector in vectors if vector["case_id"] == only]

def render(value):
    return value.replace("${ACCOUNT_ID}", "000000000000").replace("${SUFFIX}", "79s5rw")

expected = {
    "actions": sorted({render(action) for vector in vectors for action in vector["action_names"]}),
    "resources": sorted({render(resource) for vector in vectors for resource in vector["resource_arns"]}),
}
output_path.write_text(json.dumps(expected, sort_keys=True) + "\n", encoding="utf-8")
PY
  env -u AWS_PROFILE \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO="$scenario" \
    FAKE_AWS_RESPONSE="$response" \
    FAKE_AWS_EXPECTED_INPUTS="$expected_inputs" \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$test_runner" --plan "${IAM_SIM_TEST_PLAN:-$phase2_plan}" \
      --vectors "$vectors" --report "$report" "$@"
}

expect_runner_failure() {
  local label=$1
  local expected=$2
  local scenario=$3
  local response=$4
  local vectors=$5
  shift 5
  local output rc fail_line case_id report="$phase2_dir/failure-${label// /-}.json"
  case_id="$(mutation_case_id_from_label "$label")"
  reset_phase2_fake
  set +e
  if grep -Fxq "$case_id" "$mutation_dispatches"; then
    output="$(run_phase2_runner "$scenario" "$response" "$vectors" "$report" "$@" 2>&1)"
  else
    output="$(dispatch_registered_mutation "$case_id" \
      "$scenario" "$response" "$vectors" "$report" "$@" 2>&1)"
  fi
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq -- "$expected" <<<"$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}

assert_plan_refusal() {
  local lane=$1 plan=$2 expected=$3 executable=$4 core=$5 label=$6
  local output rc fail_line
  reset_phase2_fake
  set +e
  case "$lane" in
    runner)
      output="$(
        IAM_SIM_TEST_PLAN="$plan" IAM_SIM_TEST_RUNNER="$executable" \
          IAM_SIM_CORE="$core" run_phase2_runner \
            success "$phase2_dir/response-baseline.json" \
            "$phase2_dir/runner-vectors" \
            "$phase2_dir/plan-refusal-runner-report.json" 2>&1
      )"
      rc=$?
      ;;
    role-lane)
      output="$(
        IAM_SIM_TEST_ROLE_PLAN="$plan" IAM_SIM_TEST_ROLE_LANE="$executable" \
          IAM_SIM_TEST_CORE="$core" run_phase2_role_lane success --dry-run 2>&1
      )"
      rc=$?
      ;;
    *)
      output="FAIL: unknown plan-refusal lane: $lane"
      rc=2
      ;;
  esac
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [[ "$fail_line" == "$expected"* ]]; then
    return 0
  fi
  printf 'FAIL: %s did not enforce expected refusal: rc=%s observed=%s\n' \
    "$label" "$rc" "${fail_line:-<none>}" >&2
  return 1
}


run_plan_guard_case() {
  local lane=$1 guard=$2 fixture=$3 expected=$4
  local case_id label executable mutant output
  case "$lane" in
    runner)
      label="runner plan ${guard//-/ } guard"
      executable=$IAM_SIM_RUNNER
      ;;
    role-lane)
      label="role lane plan ${guard//-/ } guard"
      executable=$IAM_SIM_ROLE_LANE
      ;;
    *)
      fail_case "plan guard contract setup" "unknown lane: $lane"
      return
      ;;
  esac
  case_id="$lane-plan-$guard-guard"
  mutant="$phase2_dir/$lane-${guard}-guard-mutant"
  if output="$(assert_plan_refusal \
    "$lane" "$phase2_dir/$fixture" "$expected" \
    "$executable" "$IAM_SIM_CORE" "$label" 2>&1)"; then
    pass_case "$label refuses doctored fixture"
  else
    fail_case "$label doctored fixture" "$output"
    return
  fi
  if ! output="$(dispatch_registered_mutation "$case_id" \
    "$executable" "$mutant" 2>&1)"; then
    fail_case "$label mutation setup" "$output"
    return
  fi
  expect_failure "$label" "$label did not enforce expected refusal" \
    assert_plan_refusal \
      "$lane" "$phase2_dir/$fixture" "$expected" \
      "$mutant" "$IAM_SIM_CORE" "$label"
  if output="$(assert_plan_refusal \
    "$lane" "$phase2_dir/$fixture" "$expected" \
    "$executable" "$IAM_SIM_CORE" "$label" 2>&1)"; then
    pass_case "$label mutation restored PASS"
  else
    fail_case "$label mutation restoration" "$output"
  fi
}


run_runner_plan_guard_contracts() {
  local guard fixture expected
  while IFS='|' read -r guard fixture expected; do
    run_plan_guard_case runner "$guard" "$fixture" "$expected"
  done <<'PLAN_GUARDS'
resources-array|plan-resources-object.json|FAIL: plan planned_values.root_module.resources must be an array
exactly-one-document|plan-duplicate-document.json|FAIL: plan must contain exactly one aws_iam_role_policy.plan_reader_deny, found 2
nonempty-policy|plan-null-policy.json|FAIL: plan policy document is null, unknown, or empty: aws_iam_role_policy.plan_reader_deny
role-name|plan-null-role-name.json|FAIL: plan reader role name is null or unknown
suffix|plan-invalid-role-name.json|FAIL: cannot derive SUFFIX from plan reader role name: invalid-plan-reader
account-id-uniqueness|plan-multiple-account-ids.json|FAIL: plan policy documents contain multiple account ids:
PLAN_GUARDS
}


run_sid_contracts() {
  local lane=$1 expected="FAIL: submitted statement 0 must carry a non-empty Sid"
  local case_id label description executable mutant output
  case "$lane" in
    runner)
      label="runner empty Sid shared core guard"
      description=runner
      executable=$IAM_SIM_RUNNER
      ;;
    role-lane)
      label="role lane empty Sid shared core guard"
      description="role lane"
      executable=$IAM_SIM_ROLE_LANE
      ;;
    *)
      fail_case "Sid contract setup" "unknown lane: $lane"
      return
      ;;
  esac
  case_id="$lane-empty-sid-shared-core-guard"
  mutant="$phase2_dir/$lane-empty-sid-core-mutant.py"
  if output="$(assert_plan_refusal \
    "$lane" "$phase2_dir/plan-empty-sid.json" "$expected" \
    "$executable" "$IAM_SIM_CORE" "$label" 2>&1)"; then
    pass_case "$description refuses empty Sid at statement index 0"
  else
    fail_case "$description refuses empty Sid at statement index 0" "$output"
    return
  fi
  if ! output="$(dispatch_registered_mutation "$case_id" "$mutant" 2>&1)"; then
    fail_case "$label mutation setup" "$output"
    return
  fi
  expect_failure "$label" "$label did not enforce expected refusal" \
    assert_plan_refusal \
      "$lane" "$phase2_dir/plan-empty-sid.json" "$expected" \
      "$executable" "$mutant" "$label"
  if output="$(assert_plan_refusal \
    "$lane" "$phase2_dir/plan-empty-sid.json" "$expected" \
    "$executable" "$IAM_SIM_CORE" "$label" 2>&1)"; then
    pass_case "$label mutation restored PASS"
  else
    fail_case "$label mutation restoration" "$output"
  fi
  if output="$(assert_plan_refusal \
    "$lane" "$phase2_dir/plan-whitespace-sid.json" "$expected" \
    "$executable" "$IAM_SIM_CORE" "$description whitespace Sid guard" 2>&1)"; then
    pass_case "$description refuses whitespace-only Sid at statement index 0"
  else
    fail_case "$description refuses whitespace-only Sid at statement index 0" "$output"
  fi
}



run_real_vector_runner() {
  local vectors=$1
  local report=$2
  local plan="${IAM_SIM_CONTRACT_PLAN:-$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json}"
  env -u AWS_PROFILE -u AWS_ENDPOINT_URL \
    AWS_CLI_BIN="$phase2_fake_aws" \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO=success \
    FAKE_AWS_RESPONSE="$phase2_dir/response-empty.json" \
    FAKE_AWS_EXPECTED_INPUTS= \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$IAM_SIM_RUNNER" --plan "$plan" --vectors "$vectors" --report "$report"
}

validate_real_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-real-report "$@"
}

mutate_real_report_drop_shared() {
  python3 - "$1" "$2" <<'PY'
import json
from pathlib import Path
import sys

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for index, record in enumerate(source["records"]):
    if record.get("shared_call_case_ids"):
        del source["records"][index]
        break
else:
    raise SystemExit("FAIL: report mutation found no shared-call case")
source["summary"]["total"] = len(source["records"])
Path(sys.argv[2]).write_text(
    json.dumps(source, indent=2) + "\n", encoding="utf-8"
)
PY
}

mutate_colliding_expectation() {
  python3 - "$1" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
envelope = json.loads(path.read_text(encoding="utf-8"))
case = next(
    item for item in envelope["cases"]
    if item["case_id"]
    == "case:aws_iam_policy.deployer_iam:DenyRoleMutationMissingBoundary:ALL:none:protected-resource"
)
case["expect"]["decision"] = "implicitDeny"
path.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")
PY
}

mutate_shared_core_overlap() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-shared-core-overlap "$IAM_SIM_CORE" "$@"
}

mutate_shared_core_scanner() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-shared-core-scanner \
    "$IAM_SIM_CORE" "$@" "$submode"
}

instrument_core_counter() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-core-counter "$IAM_SIM_CORE" "$1"
}


mutate_core_sid_validation() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-core-sid-validation "$IAM_SIM_CORE" "$1"
}


mutate_plan_guard() {
  local submode=$1 lane guard
  shift
  lane=${submode%%.*}
  guard=${submode#*.}
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-plan-guard \
    "$1" "$2" "$REPO_ROOT" "$lane" "$guard"
}


validate_core_map_many() {
  jq -cn \
    --slurpfile response "$phase2_dir/response-baseline.json" \
    --slurpfile plan "$phase2_plan" '
      ($plan[0].planned_values.root_module.resources[]
        | select(.address == "aws_iam_role_policy.plan_reader_deny")
        | .values.policy) as $policy
      | {
          items: [range(0; 2) | {
            response: $response[0],
            request: {
              action_names: ["s3:GetObject"],
              resource_arns: [
                "arn:aws:s3:::orbit-infra-79s5rw-good/example",
                "arn:aws:s3:::orbit-infra-79s5rw-bad/example"
              ],
              policy_input_list: [$policy],
              permissions_boundary_policy_input_list: []
            }
          }]
        }
    ' | python3 "$IAM_SIM_CORE" map-many | jq -e '
      .results | length == 2
      and all(.[];
        .matched_sids == ["DenyReadStateObjectsOutsideScope", "FixtureAllow"]
        and .decision_observed == {
          "arn:aws:s3:::orbit-infra-79s5rw-bad/example": "explicitDeny",
          "arn:aws:s3:::orbit-infra-79s5rw-good/example": "allowed"
        }
      )
    ' >/dev/null
}


run_authorization_split_runner() {
  local core=$1
  local report=$2
  local vector_dir=${3:-$phase2_dir/authorization-split-vectors}
  local expected_inputs=${4:-$phase2_dir/expected-authorization-split-inputs.json}
  env -u AWS_PROFILE \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO=authorization-split \
    FAKE_AWS_RESPONSE="$phase2_dir/response-empty.json" \
    FAKE_AWS_EXPECTED_INPUTS="$expected_inputs" \
    IAM_SIM_CORE="$core" \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$IAM_SIM_RUNNER" --plan "$phase2_plan" \
      --vectors "$vector_dir" \
      --report "$report"
}


run_runner_target_refusal() {
  env PATH="$phase2_dir/bin:$PATH" AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" FAKE_ROLE_STATE_DIR="$phase2_roles" \
    TARGET=localstack "$IAM_SIM_RUNNER" --plan "$phase2_plan" \
    --vectors "$phase2_dir/runner-vectors" \
    --report "$phase2_dir/target.json"
}


run_casefold_authorization_partition_mutation() {
  local report=$1 mutant="$phase2_dir/iam-simulate-core-case-sensitive.py"
  local output rc
  python3 - "$IAM_SIM_CORE" "$mutant" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
old = "        frozenset(member.casefold() for member in action_class)\n"
new = "        frozenset(action_class)\n"
if source.count(old) != 1:
    raise SystemExit("FAIL: authorization case-fold mutation anchor changed")
Path(sys.argv[2]).write_text(source.replace(old, new, 1), encoding="utf-8")
PY
  reset_phase2_fake
  set +e
  output="$(run_authorization_split_runner \
    "$mutant" "$report" "$phase2_dir/authorization-casefold-vectors" \
    "$phase2_dir/expected-authorization-casefold-inputs.json" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && grep -Fq 'Invalid Input Actions:' <<<"$output"; then
    echo "FAIL: lower-case s3:deletebucketpublicaccessblock was not partitioned into the second authorization class" >&2
    return 1
  fi
  echo "FAIL: authorization case-fold mutant did not trigger the fake refusal: rc=$rc output=$output" >&2
  return 1
}


run_iam_simulate_runner_contracts() {
  local census disagreement_vectors expected_inputs isolated_policy output real_rc report report_mutant
  echo "== iam simulate contracts: RUNNER =="
  group_failures=$failures
  phase2_setup

  if validate_core_map_many; then
    pass_case "shared core maps multiple independent responses in one invocation"
  else
    fail_case "shared core maps multiple independent responses in one invocation"
  fi

  if [ ! -x "$IAM_SIM_RUNNER" ]; then
    fail_case "custom-lane runner exists and is executable" "$IAM_SIM_RUNNER is missing"
  else
    run_sid_contracts runner
    run_runner_plan_guard_contracts

    reset_phase2_fake
    report="$phase2_dir/runner-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors" "$report" 2>&1)" && \
       jq -e '
         .redaction_applied == true
         and (.recorded_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
         and (.records | length) == 1
         and .records[0].decision_observed == {"arn:aws:s3:::orbit-infra-79s5rw-bad/example":"explicitDeny","arn:aws:s3:::orbit-infra-79s5rw-good/example":"allowed"}
         and .records[0].matched_sids == ["DenyReadStateObjectsOutsideScope","FixtureAllow"]
         and .records[0].pass == true
         and (.records[0].document_hashes_submitted.policy_input_list | length) == 1
       ' "$report" >/dev/null; then
      pass_case "runner maps nested per-resource decisions and source positions"
    else
      fail_case "runner maps nested per-resource decisions and source positions" "$output"
    fi

    expect_runner_failure "runner per-resource mapper" "decision mismatch" \
      success "$phase2_dir/response-decision-mutant.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner position-to-Sid attribution" "required matched Sid is absent" \
      success "$phase2_dir/response-position-mutant.json" "$phase2_dir/runner-vectors"

    IAM_SIM_TEST_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      expect_runner_failure "runner per-pair required Sid" \
        "required matched Sid is absent for s3:GetObjectVersion *: DenyReadStateObjectsOutsideScope" \
        success "$phase2_dir/response-per-pair-sid-mutant.json" \
        "$phase2_dir/per-pair-sid-vectors"

    reset_phase2_fake
    report="$phase2_dir/per-pair-sid-restored-report.json"
    if output="$(IAM_SIM_TEST_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      run_phase2_runner success "$phase2_dir/response-per-pair-sid-restored.json" \
        "$phase2_dir/per-pair-sid-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].pass == true
         and (.[0].details | length) == 2
         and all(.[0].details[];
           .matched_sids | index("DenyReadStateObjectsOutsideScope") != null
         )
       ' "$report" >/dev/null; then
      pass_case "runner per-pair required Sid restored"
    else
      fail_case "runner per-pair required Sid restored" "$output"
    fi

    for name in real-position multiline-position; do
      reset_phase2_fake
      report="$phase2_dir/$name-report.json"
      if output="$(IAM_SIM_TEST_PLAN="$phase2_dir/plan-$name.json" \
        run_phase2_runner success "$phase2_dir/response-$name.json" \
          "$phase2_dir/$name-vectors" "$report" 2>&1)" && \
         jq -e '
           .records | length == 1
           and .[0].matched_sids == ["DenyReadStateObjectsOutsideScope"]
           and .[0].pass == true
         ' "$report" >/dev/null; then
        pass_case "runner maps $name exact statement span"
      else
        fail_case "runner maps $name exact statement span" "$output"
      fi
    done

    for name in string-delimiters escaped-quotes; do
      reset_phase2_fake
      report="$phase2_dir/scanner-$name-report.json"
      if output="$(IAM_SIM_TEST_PLAN="$phase2_dir/plan-scanner-position.json" \
        run_phase2_runner success "$phase2_dir/response-scanner-$name.json" \
          "$phase2_dir/scanner-$name-vectors" "$report" 2>&1)" && \
         jq -e '.records | length == 1 and .[0].pass == true' \
           "$report" >/dev/null; then
        pass_case "runner scans exact statement spans with $name"
      else
        fail_case "runner scans exact statement spans with $name" "$output"
      fi
    done

    reset_phase2_fake
    report="$phase2_dir/deployer-position-report.json"
    if output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      run_phase2_runner success "$phase2_dir/response-deployer-position.json" \
        "$phase2_dir/deployer-position-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].matched_sids == ["ClickhouseSecretCreateWithTag"]
         and .[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner maps real deployer_data delimiter-inclusive range"
    else
      fail_case "runner maps real deployer_data delimiter-inclusive range" "$output"
    fi
    IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      expect_runner_failure "runner real deployer_data two-statement overlap refusal" \
        "ambiguous matched statement position from PolicyInputList.1: overlap_count=2 document_length=5682 statement_span_count=18 returned_range=[1777,2054) first_span=[14,112):EcrVerificationAuth last_span=[4809,5657):EnvDataBucketLifecycle" \
        success "$phase2_dir/response-deployer-ambiguous.json" \
        "$phase2_dir/deployer-position-vectors"

    reset_phase2_fake
    report="$phase2_dir/resolved-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-resolved.json" \
      "$phase2_dir/ambiguous-vectors" "$report" 2>&1)" && \
       assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
         "aws_iam_policy.task_boundary" "--policy-input-list" && \
       assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
         "aws_iam_policy.task_boundary" "--permissions-boundary-policy-input-list"; then
      pass_case "runner resolves policy and boundary bytes from plan addresses"
    else
      fail_case "runner resolves policy and boundary bytes from plan addresses" "$output"
    fi
    if dispatch_registered_mutation runner-plan-policy-byte-equality \
      "$phase2_calls"; then
      expect_failure "runner plan policy byte equality" \
        "submitted --policy-input-list document differs from plan text" \
        assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
          "aws_iam_policy.task_boundary" "--policy-input-list"
    else
      fail_case "runner plan policy byte equality mutation setup" "no simulator call"
    fi
    if dispatch_registered_mutation runner-boundary-policy-byte-equality \
      "$phase2_calls"; then
      expect_failure "runner boundary policy byte equality" \
        "submitted --permissions-boundary-policy-input-list document differs from plan text" \
        assert_submitted_document_equals_plan "$phase2_plan" "$phase2_calls" \
          "aws_iam_policy.task_boundary" "--permissions-boundary-policy-input-list"
    else
      fail_case "runner boundary policy byte equality mutation setup" "no simulator call"
    fi

    reset_phase2_fake
    report="$phase2_dir/action-level-star-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-action-level.json" \
      "$phase2_dir/ambiguous-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].decision_observed == "allowed"
         and .[0].matched_sids == ["EcrAuth"]
         and .[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner uses action-level decision and attribution for explicit star"
    else
      fail_case "runner uses action-level decision and attribution for explicit star" "$output"
    fi
    expect_runner_failure "runner action-level explicit-star decision" \
      "decision mismatch for ecr:GetAuthorizationToken *: expected allowed, observed implicitDeny" \
      success "$phase2_dir/response-action-level-decision-mutant.json" \
      "$phase2_dir/ambiguous-vectors"

    reset_phase2_fake
    report="$phase2_dir/action-level-no-resource-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-action-level.json" \
      "$phase2_dir/no-resource-vectors" "$report" 2>&1)" && \
       jq -e '
         .records | length == 1
         and .[0].decision_observed == "allowed"
         and .[0].matched_sids == ["EcrAuth"]
         and .[0].pass == true
       ' "$report" >/dev/null && \
       jq -e 'index("--resource-arns") == null' "$phase2_calls/1.json" >/dev/null; then
      pass_case "runner uses action-level decision and attribution with no submitted resource"
    else
      fail_case "runner uses action-level decision and attribution with no submitted resource" "$output"
    fi
    expect_runner_failure "runner action-level no-resource attribution" \
      "required matched Sid is absent: EcrAuth" \
      success "$phase2_dir/response-action-level-attribution-mutant.json" \
      "$phase2_dir/no-resource-vectors"

    expect_runner_failure "runner multiple-concrete action-level refusal" \
      "action-level result lacks ResourceSpecificResults for s3:GetObject" \
      success "$phase2_dir/response-multiple-concrete-action-level.json" \
      "$phase2_dir/runner-vectors"
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-real-position.json" \
      expect_runner_failure "runner missing exact concrete ARN refusal" \
        "submitted resource ARN is absent from response: s3:GetObject arn:aws:s3:::orbit-infra-79s5rw-tfstate/other/x" \
        success "$phase2_dir/response-missing-concrete-arn.json" \
        "$phase2_dir/real-position-vectors"

    IAM_SIM_TEST_PLAN="$phase2_dir/plan-missing-document.json" \
      expect_runner_failure "runner missing named document" \
        "named policy document is absent from plan: aws_iam_policy.task_boundary" \
        success "$phase2_dir/response-resolved.json" "$phase2_dir/ambiguous-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner missing named document" "fake AWS was called"
    fi
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-missing-sid.json" \
      expect_runner_failure "runner missing named Sid" \
        "named Sid is absent from plan policy aws_iam_policy.deployer_data: LogsCreateWithTag" \
        success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner missing named Sid" "fake AWS was called"
    fi
    IAM_SIM_TEST_PLAN="$phase2_dir/plan-duplicate-sid.json" \
      expect_runner_failure "runner duplicate named Sid" \
        "named Sid matches more than one statement in plan policy aws_iam_policy.deployer_data: LogsCreateWithTag" \
        success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "runner duplicate named Sid" "fake AWS was called"
    fi

    expect_runner_failure "runner ambiguous position refusal" "ambiguous matched statement position" \
      success "$phase2_dir/response-ambiguous.json" "$phase2_dir/ambiguous-vectors"
    expect_runner_failure "runner unmapped position refusal" \
      "unmapped matched statement position from PolicyInputList.1: unmapped_offset=0 document_length=288 statement_span_count=2 returned_range=[0,1) first_span=[37,152):FixtureAllow last_span=[153,286):DenyReadStateObjectsOutsideScope" \
      success "$phase2_dir/response-unmapped.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner unknown source-label refusal" \
      "unrecognised SourcePolicyId UnknownPolicyLabel; submitted labels: PolicyInputList.1" \
      success "$phase2_dir/response-unknown-source.json" "$phase2_dir/runner-vectors"
    expect_runner_failure "runner missing submitted ARN refusal" "submitted resource ARN is absent" \
      success "$phase2_dir/response-missing-arn.json" "$phase2_dir/runner-vectors"

    reset_phase2_fake
    report="$phase2_dir/shared-call-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-duplicate.json" \
      "$phase2_dir/duplicate-vectors" "$report" 2>&1)" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 1 ] && \
       jq -e '
         .records | length == 2
         and .[0].decision_observed == "allowed"
         and .[1].decision_observed == "allowed"
         and .[0].matched_sids == []
         and .[1].matched_sids == []
         and .[0].shared_call_case_ids == [.[1].case_id]
         and .[1].shared_call_case_ids == [.[0].case_id]
         and all(.[]; .pass == true)
       ' "$report" >/dev/null; then
      pass_case "runner emits one observed record per compatible shared-call case"
    else
      fail_case "runner emits one observed record per compatible shared-call case" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/authorization-split-report.json"
    expected_inputs="$phase2_dir/expected-authorization-split-inputs.json"
    if output="$(run_authorization_split_runner "$IAM_SIM_CORE" "$report" 2>&1)" && \
       python3 - "$phase2_calls" "$expected_inputs" <<'PY' &&
import json
from pathlib import Path
import sys


calls = []
for path in sorted(Path(sys.argv[1]).glob("*.json")):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] != ["iam", "simulate-custom-policy"]:
        continue
    index = args.index("--action-names") + 1
    actions = []
    while index < len(args) and not args[index].startswith("--"):
        actions.append(args[index])
        index += 1
    calls.append(sorted(actions))
expected = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if sorted(calls) != sorted(expected["required_action_groups"]):
    raise SystemExit(
        f"FAIL: authorization action groups differ: {json.dumps(calls)}"
    )
PY
       jq -e '
         .summary == {"failed":0,"passed":1,"runner_failures":0,"total":1}
         and .records[0].decision_observed == "allowed"
         and .records[0].matched_sids == []
         and .records[0].pass == true
       ' "$report" >/dev/null; then
      pass_case "runner splits S3 operations that require different authorization information"
    else
      fail_case "runner splits S3 operations that require different authorization information" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/real-vector-report.json"
    set +e
    # shellcheck disable=SC2153 # VECTORS is provided by the sourcing suite.
    output="$(run_real_vector_runner "$VECTORS" "$report" 2>&1)"
    real_rc=$?
    set -e
    if [ "$real_rc" -ne 0 ] && \
       grep -Fq 'AWS simulator response lacks EvaluationResults array' <<<"$output" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 231 ] && \
       census="$(validate_real_report "$VECTORS" "$report" 2>&1)"; then
      pass_case "real-vector batch safety and report completeness -> $census"
    else
      fail_case "real-vector batch safety and report completeness" \
        "rc=$real_rc calls=$(phase2_call_count iam simulate-custom-policy) output=$output"
    fi

    report_mutant="$phase2_dir/real-vector-report-dropped-shared-case.json"
    dispatch_registered_mutation real-report-dropped-shared-case       "$report" "$report_mutant"
    expect_failure "real report dropped shared case" "report omits selected case_id"       validate_real_report "$VECTORS" "$report_mutant"

    disagreement_vectors="$phase2_dir/real-disagreement-vectors"
    cp -R "$VECTORS" "$disagreement_vectors"
    dispatch_registered_mutation real-colliding-case-expectation-disagreement       "$disagreement_vectors/aws_iam_policy.deployer_iam__DenyRoleMutationMissingBoundary.json"
    IAM_SIM_TEST_PLAN="${IAM_SIM_CONTRACT_PLAN:-$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json}" \
      expect_runner_failure "real colliding-case expectation disagreement" \
        "expectation-disagreeing duplicate action/resource pair in batch" \
        success "$phase2_dir/response-empty.json" "$disagreement_vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 0 ]; then
      fail_case "real colliding-case expectation disagreement" "fake AWS was called"
    fi

    reset_phase2_fake
    report="$phase2_dir/throttle-report.json"
    if output="$(run_phase2_runner throttle-once "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors" "$report" 2>&1)" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 2 ]; then
      pass_case "runner retries throttling once and then succeeds"
    else
      fail_case "runner retries throttling once and then succeeds" "$output"
    fi
    expect_runner_failure "runner throttle attempt cap" "failed after 5 attempts" \
      throttle-always "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 5 ]; then
      fail_case "runner throttle attempt cap" "expected 5 fake calls"
    fi

    expect_runner_failure "runner timeout no-retry" "timed out with exit 124" \
      timeout "$phase2_dir/response-baseline.json" "$phase2_dir/runner-vectors"
    if [ "$(phase2_call_count iam simulate-custom-policy)" -ne 1 ]; then
      fail_case "runner timeout no-retry" "timeout was retried"
    elif ! jq -e '. as $report | (($report.records | length) == 1 and $report.records[0].decision_observed == null and $report.records[0].runner_failure == "AWS simulator timed out with exit 124" and $report.summary.runner_failures == 1)' \
      "$phase2_dir/failure-runner-timeout-no-retry.json" >/dev/null; then
      fail_case "runner timeout no-retry" "timeout was recorded as a decision"
    fi

    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation runner-target-refusal 2>&1)"
    target_rc=$?
    set -e
    if [ "$target_rc" -ne 0 ] && grep -Fq 'FAIL: TARGET must be exactly aws' <<<"$output" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 0 ]; then
      pass_case "runner TARGET refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "runner TARGET refusal mutation did not fail as required" "$output"
    fi

    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation \
      runner-shared-authorization-partition \
      "$phase2_authorization_core_mutant" "$report" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [[ "$fail_line" == "FAIL: AWS simulator call failed with exit 254: An error occurred (InvalidInput) when calling the SimulateCustomPolicy operation: Invalid Input Actions: "*" require different authorization information." ]]; then
      pass_case "runner shared authorization partition mutation -> $fail_line"
    else
      fail_case "runner shared authorization partition mutation did not fail as required" \
        "rc=$rc output=$output"
    fi
    reset_phase2_fake
    if output="$(run_authorization_split_runner "$IAM_SIM_CORE" "$report" 2>&1)" && \
       [ "$(phase2_call_count iam simulate-custom-policy)" -eq 2 ]; then
      pass_case "runner shared authorization partition mutation restored PASS"
    else
      fail_case "runner shared authorization partition mutation restoration" "$output"
    fi

    report="$phase2_dir/authorization-casefold-report.json"
    expect_failure "runner case-insensitive S3 authorization partition"       "lower-case s3:deletebucketpublicaccessblock was not partitioned into the second authorization class"       dispatch_registered_mutation         runner-case-insensitive-s3-authorization-partition "$report"
    reset_phase2_fake
    if output="$(run_authorization_split_runner       "$IAM_SIM_CORE" "$report"       "$phase2_dir/authorization-casefold-vectors"       "$phase2_dir/expected-authorization-casefold-inputs.json" 2>&1)"; then
      pass_case "runner case-insensitive S3 authorization partition mutation restored PASS"
    else
      fail_case "runner case-insensitive S3 authorization partition mutation restoration" "$output"
    fi

    reset_phase2_fake
    report="$phase2_dir/isolated-report.json"
    if output="$(run_phase2_runner success "$phase2_dir/response-isolated.json" "$phase2_dir/isolated-vectors" "$report" 2>&1)"; then
      isolated_policy="$(python3 - "$phase2_calls" <<'PY'
import json
from pathlib import Path
import sys
for path in Path(sys.argv[1]).glob("*.json"):
    args = json.loads(path.read_text(encoding="utf-8"))
    if args[:2] == ["iam", "simulate-custom-policy"]:
        index = args.index("--policy-input-list")
        print(args[index + 1])
        break
PY
)"
      if jq -e '.Statement | length == 1 and .[0].Sid == "LogsCreateWithTag"' <<<"$isolated_policy" >/dev/null; then
        pass_case "runner wraps an isolated vector as one statement"
      else
        fail_case "runner wraps an isolated vector as one statement" "$isolated_policy"
      fi
    else
      fail_case "runner wraps an isolated vector as one statement" "$output"
    fi
    expect_runner_failure "runner isolated one-statement decision" "decision mismatch" \
      success "$phase2_dir/response-isolated-mutant.json" "$phase2_dir/isolated-vectors"
    expect_runner_failure "runner isolated wrapper position attribution" \
      "forbidden matched Sid is present: LogsCreateWithTag" \
      success "$phase2_dir/response-isolated-position-mutant.json" \
        "$phase2_dir/isolated-vectors"

    core_mutant="$phase2_dir/iam-simulate-core-strict-containment.py"
    for name in two-statement real-deployer; do
      dispatch_registered_mutation \
        "runner-$name-shared-core-unique-overlap" "$core_mutant"
      reset_phase2_fake
      if [ "$name" = two-statement ]; then
        mutant_plan="$phase2_plan"
        mutant_response="$phase2_dir/response-baseline.json"
        mutant_vectors="$phase2_dir/runner-vectors"
      else
        mutant_plan="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json"
        mutant_response="$phase2_dir/response-deployer-position.json"
        mutant_vectors="$phase2_dir/deployer-position-vectors"
      fi
      set +e
      output="$(IAM_SIM_CORE="$core_mutant" IAM_SIM_TEST_PLAN="$mutant_plan" \
        run_phase2_runner success "$mutant_response" "$mutant_vectors" \
          "$phase2_dir/strict-$name-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && \
         grep -Fq 'FAIL: unmapped matched statement position from PolicyInputList.1' \
           <<<"$output"; then
        pass_case "runner $name shared-core unique-overlap mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name shared-core unique-overlap mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

    for name in string-delimiters escaped-quotes; do
      core_mutant="$phase2_dir/iam-simulate-core-$name-mutant.py"
      dispatch_registered_mutation \
        "runner-$name-shared-core-scanner" "$core_mutant"
      reset_phase2_fake
      set +e
      output="$(IAM_SIM_CORE="$core_mutant" \
        IAM_SIM_TEST_PLAN="$phase2_dir/plan-scanner-position.json" \
        run_phase2_runner success "$phase2_dir/response-scanner-$name.json" \
          "$phase2_dir/scanner-$name-vectors" \
          "$phase2_dir/$name-mutant-report.json" 2>&1)"
      mutant_rc=$?
      set -e
      if [ "$mutant_rc" -ne 0 ] && grep -Fq 'FAIL: cannot scan submitted statement:' \
        <<<"$output"; then
        pass_case "runner $name shared-core scanner mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
      else
        fail_case "runner $name shared-core scanner mutation did not fail as required" \
          "rc=$mutant_rc output=$output"
      fi
    done

    reset_phase2_fake
    report="$phase2_dir/shared-core-restored-report.json"
    if output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      run_phase2_runner success "$phase2_dir/response-deployer-position.json" \
        "$phase2_dir/deployer-position-vectors" "$report" 2>&1)" && \
       jq -e '.records | length == 1 and .[0].pass == true' "$report" >/dev/null; then
      pass_case "runner shared-core mutations restored PASS"
    else
      fail_case "runner shared-core mutation restoration" "$output"
    fi

    local context_mutant="$phase2_dir/iam-simulate-no-context.sh"
    dispatch_registered_mutation runner-custom-context-entry-preservation \
      "$IAM_SIM_RUNNER" "$context_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_RUNNER="$context_mutant" run_phase2_runner \
      context-required "$phase2_dir/response-deployer-position.json" \
      "$phase2_dir/deployer-position-vectors" \
      "$phase2_dir/custom-context-mutant-report.json" 2>&1)"
    mutant_rc=$?
    set -e
    fail_line="$(grep -m1 'FAIL: fake simulate-custom-policy context entries mismatch:' <<<"$output" || true)"
    if [ "$mutant_rc" -ne 0 ] && [ -n "$fail_line" ]; then
      pass_case "runner custom context-entry preservation mutation -> $fail_line"
    else
      fail_case "runner custom context-entry preservation mutation did not fail" \
        "rc=$mutant_rc output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_TEST_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      run_phase2_runner context-required \
      "$phase2_dir/response-deployer-position.json" \
      "$phase2_dir/deployer-position-vectors" \
      "$phase2_dir/custom-context-restored-report.json" 2>&1)"; then
      pass_case "runner custom context-entry preservation mutation restored PASS"
    else
      fail_case "runner custom context-entry preservation mutation restoration" "$output"
    fi

    runner_mutant="$phase2_dir/iam-simulate-wrong-resource.sh"
    python3 - "$IAM_SIM_RUNNER" "$runner_mutant" "$REPO_ROOT" <<'PY_MUTANT'
from pathlib import Path
import shlex
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
root_line = 'REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
resource_line = 'resources = sorted({resource for item in batch for resource in item["vector"]["resource_arns"]})'
if source.count(root_line) != 1 or source.count(resource_line) != 1:
    raise SystemExit("FAIL: runner wrong-resource mutation anchors changed")
source = source.replace(root_line, f"REPO_ROOT={shlex.quote(sys.argv[3])}")
source = source.replace(resource_line, 'resources = ["arn:aws:s3:::orbit-infra-wrong/example"]')
Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY_MUTANT
    chmod +x "$runner_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_RUNNER="$runner_mutant" \
      dispatch_registered_mutation runner-fake-resource-set-enforcement \
        success "$phase2_dir/response-baseline.json" \
        "$phase2_dir/runner-vectors" \
        "$phase2_dir/wrong-resource-report.json" 2>&1)"
    mutant_rc=$?
    set -e
    if [ "$mutant_rc" -ne 0 ] && \
       grep -Fq 'FAIL: fake simulate-custom-policy resource ARNs mismatch:' <<<"$output"; then
      pass_case "runner fake resource-set enforcement mutation -> $(grep -m1 'FAIL: fake simulate-custom-policy resource ARNs mismatch:' <<<"$output")"
    else
      fail_case "runner fake resource-set enforcement mutation did not fail as required" "rc=$mutant_rc output=$output"
    fi
  fi

  if [ "$failures" -eq "$group_failures" ]; then
    echo "PASS: IAM simulate RUNNER group"
  else
    echo "FAIL: IAM simulate RUNNER group" >&2
  fi
}

run_phase2_role_lane() {
  local scenario=$1
  local test_account="${IAM_SIM_TEST_ACCOUNT_ID:-000000000000}"
  local test_plan="${IAM_SIM_TEST_ROLE_PLAN:-$phase2_plan}"
  local test_vectors="${IAM_SIM_TEST_ROLE_VECTORS:-$phase2_dir/role-vectors}"
  local test_report="${IAM_SIM_TEST_ROLE_REPORT:-$phase2_dir/role-report.json}"
  local test_custom_report="${IAM_SIM_TEST_ROLE_CUSTOM_REPORT:-$phase2_dir/role-custom-report.json}"
  local test_role_lane="${IAM_SIM_TEST_ROLE_LANE:-$IAM_SIM_ROLE_LANE}"
  local test_run_id="${IAM_SIM_TEST_RUN_ID:-fixture-run}"
  shift
  env -u AWS_PROFILE \
    PATH="$phase2_dir/bin:$PATH" \
    AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" \
    FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" \
    FAKE_AWS_SCENARIO="$scenario" \
    FAKE_PRINCIPAL_RESPONSE="${IAM_SIM_TEST_PRINCIPAL_RESPONSE:-}" \
    FAKE_ACCOUNT_ID="$test_account" \
    FAKE_ROLE_FAILURE_CREATE_INDEX="${IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX:-}" \
    FAKE_ROLE_INJECTION_SUFFIX="${IAM_SIM_TEST_ROLE_INJECTION_SUFFIX:-}" \
    IAM_SIM_RUN_ID="$test_run_id" \
    IAM_SIM_CORE="${IAM_SIM_TEST_CORE:-$IAM_SIM_CORE}" \
    IAM_SIM_RETRY_BASE_SECONDS=0 \
    TARGET=aws \
    "$test_role_lane" --plan "$test_plan" --vectors "$test_vectors" \
      --report "$test_report" --expect-account "$test_account" \
      --custom-report "$test_custom_report" "$@"
}

expect_role_failure() {
  local label=$1
  local expected=$2
  local scenario=$3
  shift 3
  local output rc fail_line case_id
  case_id="$(mutation_case_id_from_label "$label")"
  reset_phase2_fake
  set +e
  if grep -Fxq "$case_id" "$mutation_dispatches"; then
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane "$scenario" "$@" 2>&1)"
  else
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      dispatch_registered_mutation "$case_id" "$scenario" "$@" 2>&1)"
  fi
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq -- "$expected" <<<"$output"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail as required" "rc=$rc output=$output"
  fi
}


validate_role_account_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-account-redaction "$@"
}

validate_role_creation_failure() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-creation-failure "$@"
}

run_role_creation_failure_case() {
  local label=$1
  local scenario=$2
  local expected=$3
  local expected_role_count=$4
  local failure_index=$5
  local created_count=$6
  local test_plan=$7
  local test_vectors=$8
  local test_custom_report=$9
  local test_role_lane=${10:-$IAM_SIM_ROLE_LANE}
  local report="$phase2_dir/role-failure-$scenario-$expected_role_count-$failure_index.json"
  local output rc fail_line
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$test_plan" \
    IAM_SIM_TEST_ROLE_VECTORS="$test_vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$test_custom_report" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX="$failure_index" \
    IAM_SIM_TEST_ROLE_LANE="$test_role_lane" \
    run_phase2_role_lane "$scenario" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && [ -n "$fail_line" ] && grep -Fq -- "$expected" <<<"$output" && \
     validate_role_creation_failure \
       "$report" "$phase2_calls" "$expected_role_count" "$failure_index" "$created_count" && \
     ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
    pass_case "$label -> $fail_line"
  else
    fail_case "$label" "rc=$rc output=$output"
  fi
}


run_registered_role_creation_failure_case() {
  local case_id
  case_id="$(mutation_case_id_from_label "$1")"
  if grep -Fxq "$case_id" "$mutation_dispatches"; then
    run_role_creation_failure_case "$@"
  else
    dispatch_registered_mutation "$case_id" "$@"
  fi
}


role_wrong_hash_expected_line() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" role-wrong-hash-expected-line "$@"
}

validate_role_cleanup_race() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-cleanup-race "$@"
}

run_role_cleanup_race_case() {
  local label=$1
  local scenario=$2
  local expected_rc=$3
  local expected_failure=$4
  local report="$phase2_dir/role-$scenario-report.json"
  local output rc fail_line
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
    IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
    run_phase2_role_lane "$scenario" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -eq "$expected_rc" ] && [ -n "$fail_line" ] && \
     grep -Fq "$expected_failure" <<<"$output" && \
     validate_role_cleanup_race "$report" "$phase2_calls" "$phase2_roles" "$scenario"; then
    pass_case "$label mutation -> $fail_line"
  else
    fail_case "$label mutation did not fail safely" "rc=$rc output=$output"
  fi
}

run_registered_role_cleanup_race_case() {
  local case_id
  case_id="$(mutation_case_id_from_label "$1")"
  dispatch_registered_mutation "$case_id" "$@"
}


run_role_projection_restored_case() {
  local label=$1
  local report="$phase2_dir/role-${label// /-}-report.json"
  local output
  reset_phase2_fake
  if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
    IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    run_phase2_role_lane success 2>&1)" && \
     [ "$(phase2_call_count iam create-role)" -eq 8 ] && \
     [ "$(phase2_call_count iam delete-role)" -eq 8 ] && \
     [ "$(phase2_call_count iam get-role)" -eq 8 ] && \
     ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
    pass_case "$label restored PASS"
  else
    fail_case "$label restoration" "$output"
  fi
}

validate_role_nonce_tamper() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-nonce-tamper "$@"
}

apply_role_report_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-report-redaction "$@" "$REPO_ROOT"
  chmod +x "$2"
}

mutate_role_account_redaction() {
  apply_role_report_redaction "$1" "$2"
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-report-redaction "$3" "$4"
}

mutate_role_trust_root() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-trust-root "$@" "$REPO_ROOT"
  chmod +x "$2"
}

mutate_role_principal_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-principal-redaction "$@" "$REPO_ROOT"
  chmod +x "$2"
}

validate_role_trust_calls() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-trust-calls "$@"
}

validate_role_principal_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-principal-redaction "$@"
}

mutate_report_principal_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-report-principal-redaction "$@"
}

validate_report_principal_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-principal-redaction "$@"
}

mutate_artifact_hygiene_principal_arn() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-artifact-hygiene-principal-arn "$@"
  chmod +x "$2"
}

validate_role_per_pair() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-per-pair "$@"
}

mutate_role_context_entries() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-context-entries "$@" "$REPO_ROOT"
}

mutate_custom_context_entries() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-custom-context-entries "$@" "$REPO_ROOT"
}

validate_role_plan_account_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-plan-account-redaction "$@"
}

mutate_role_plan_account_redaction() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
payload = json.loads(source.read_text(encoding="utf-8"))
payload["plan_account"] = sys.argv[3]
destination.write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY
}

mutate_role_nonce_check() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-nonce-check "$@" "$REPO_ROOT"
  chmod +x "$2"
}

mutate_role_cleanup_high_indices() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-cleanup-high-indices "$@" "$REPO_ROOT"
  chmod +x "$2"
}

validate_role_selection_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-selection-report "$@"
}

mutate_role_selection_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-selection-report "$@"
}

mutate_role_only_selection() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-only-selection \
    "$@" "$REPO_ROOT"
}

mutate_role_custom_preflight_scope() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-custom-preflight-scope \
    "$1" "$2" "$REPO_ROOT"
}

validate_role_projection_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-projection-report "$@"
}

mutate_role_projection_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-projection-report "$@"
}

validate_role_divergence_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-divergence-report "$@"
}

mutate_role_source_logic() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-source-logic \
    "$@" "$submode" "$REPO_ROOT"
}

mutate_role_divergence_report() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-divergence-report "$@"
}

validate_role_two_runs() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-two-runs "$@"
}

validate_role_authorization_split() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-authorization-split "$@"
}

mutate_role_two_run_calls() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-two-run-calls "$@"
}

validate_readiness_inventory() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-readiness-inventory "$@"
}

validate_role_propagation() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-propagation "$@"
}

validate_role_readback_exhaustion() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-readback-exhaustion "$@"
}

validate_role_readiness_exhaustion() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-role-readiness-exhaustion "$@"
}

run_role_propagation_exhaustion() {
  local submode=$1 report=$2 scenario
  case "$submode" in
    readback) scenario=propagation-readback-exhausted ;;
    readiness) scenario=propagation-readiness-exhausted ;;
    *) echo "FAIL: unknown role propagation exhaustion mutation: $submode" >&2; return 1 ;;
  esac
  IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
    IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    run_phase2_role_lane "$scenario"
}

mutate_role_propagation_retry() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-propagation-retry \
    "$@" "$REPO_ROOT"
}

run_full_scale_role_dry_run() {
  local role_lane=$1
  local output_path=$2
  local vectors="${IAM_SIM_FULL_SCALE_VECTORS:-$REPO_ROOT/tests/fixtures/iam-simulate/vectors}"
  local timeout_seconds=${IAM_SIM_FULL_SCALE_TIMEOUT_SECONDS:-20}
  python3 "$IAM_SIM_FIXTURE_FACTORY" run-full-scale-role-dry-run \
    "$role_lane" "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" "$vectors" \
    "$output_path" "$timeout_seconds" "$phase2_dir" "$IAM_SIM_AWS_WRAPPER"
}

validate_full_scale_role_dry_run() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-full-scale-role-dry-run "$1" "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" "${IAM_SIM_FULL_SCALE_VECTORS:-$REPO_ROOT/tests/fixtures/iam-simulate/vectors}"
}

prepare_fd_vectors() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" prepare-fd-vectors \
    "$REPO_ROOT/tests/fixtures/iam-simulate/vectors" "$1" 24
}

validate_fd_leak_probe() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-fd-leak-probe "$1" 24
}

validate_fd_stability_probe() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" validate-fd-stability-probe "$1" 24
}

mutate_role_deterministic_fd_leak() {
  local submode=$1
  shift
  if [ "$submode" != "macOS-bash-3.2+Linux-bash-5" ]; then
    echo "FAIL: unknown descriptor-leak mutation: $submode" >&2
    return 1
  fi
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-deterministic-fd-leak "$@" "$REPO_ROOT"
  chmod +x "$2"
}

instrument_role_fd_reads() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" instrument-role-fd-reads "$@" "$REPO_ROOT"
  chmod +x "$2"
}

validate_dry_run_inventory() {
  local inventory=$1
  local operation expected
  if ! python3 - "$inventory" <<'PY_TRUST'
import json
import shlex
import sys

expected = "arn:aws:iam::000000000000:<redacted-principal>"
create_calls = [
    shlex.split(line.removeprefix("DRY-RUN:"))
    for line in sys.argv[1].splitlines()
    if " iam create-role " in f" {line} "
]
for call in create_calls:
    policy = json.loads(call[call.index("--assume-role-policy-document") + 1])
    principal = policy.get("Statement", [{}])[0].get("Principal")
    if principal != {"AWS": expected}:
        raise SystemExit("FAIL: dry-run create-role trust does not name only the redacted invoking identity")
PY_TRUST
  then
    return 1
  fi
  for operation in create-role put-role-policy delete-role-policy delete-role; do
    expected=3
    if [ "$(grep -Ec "iam $operation( |$)" <<<"$inventory" || true)" -ne "$expected" ]; then
      echo "FAIL: dry-run inventory requires three iam $operation calls" >&2
      return 1
    fi
  done
  if [ "$(grep -c 'iam simulate-principal-policy' <<<"$inventory" || true)" -ne 6 ] ||
     [ "$(grep -c 'iam list-role-tags' <<<"$inventory" || true)" -ne 9 ] ||
     [ "$(grep -c 'iam get-role' <<<"$inventory" || true)" -ne 3 ]; then
    echo "FAIL: dry-run inventory requires simulations, ownership reads, and absence checks" >&2
    return 1
  fi
  python3 - "$inventory" <<'PY'
import re
import sys
lines = sys.argv[1].splitlines()

def positions(operation):
    return [index for index, line in enumerate(lines) if re.search(rf" iam {operation}(?: |$)", line)]

creates = positions("create-role")
puts = positions("put-role-policy")
simulates = positions("simulate-principal-policy")
delete_policies = positions("delete-role-policy")
delete_roles = positions("delete-role")
if not (max(creates) < min(puts) < max(puts) < min(simulates) and max(simulates) < min(delete_policies)):
    raise SystemExit("FAIL: dry-run inventory phase ordering is wrong")
if any(policy >= role for policy, role in zip(delete_policies, delete_roles)):
    raise SystemExit("FAIL: dry-run inventory must delete each inline policy before its role")
PY
}

mutate_role_dry_run_inventory() {
  grep -v 'iam delete-role-policy' <<<"$1" || true
}

run_role_account_mismatch_refusal() {
  IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    env PATH="$phase2_dir/bin:$PATH" AWS_CLI_BIN=aws \
    AWS_CLI_SH="$IAM_SIM_AWS_WRAPPER" FAKE_AWS_CALL_DIR="$phase2_calls" \
    FAKE_ROLE_STATE_DIR="$phase2_roles" FAKE_AWS_SCENARIO=success \
    FAKE_ACCOUNT_ID=111111111111 IAM_SIM_RUN_ID=fixture-run TARGET=aws \
    "$IAM_SIM_ROLE_LANE" --plan "$phase2_plan" \
      --vectors "$phase2_dir/role-vectors" \
      --report "$phase2_dir/mismatch.json" --expect-account 000000000000 \
      --custom-report "$phase2_dir/role-custom-report.json"
}


run_role_shared_mapping_case() {
  local name=$1
  local label=$2
  local plan=$3
  local vectors=$4
  local custom_report=$5
  local response=$6
  local expected_sid=$7
  local report="$phase2_dir/role-shared-$name-report.json"
  local case_id custom_sha256 output rc
  case_id="$(jq -r '.records[0].case_id' "$custom_report")"
  custom_sha256="$(shasum -a 256 "$custom_report" | awk '{print $1}')"
  reset_phase2_fake
  set +e
  output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
    IAM_SIM_TEST_ROLE_PLAN="$plan" \
    IAM_SIM_TEST_ROLE_VECTORS="$vectors" \
    IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$custom_report" \
    IAM_SIM_TEST_ROLE_REPORT="$report" \
    IAM_SIM_TEST_PRINCIPAL_RESPONSE="$response" \
    run_phase2_role_lane success --only "$case_id" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ] && jq -e \
    --arg sid "$expected_sid" --arg custom_sha256 "$custom_sha256" '
    (.recorded_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and .custom_report_sha256 == $custom_sha256
    and (.records | length) == 1
    and .records[0].pass == true
    and .records[0].source_document_hash_agrees_with_custom_lane == true
    and .records[0].scp_excluded.decision_observed == "allowed"
    and .records[0].default.decision_observed == "allowed"
    and (if $sid == "" then
      .records[0].scp_excluded.matched_sids == [] and .records[0].default.matched_sids == []
    else
      .records[0].scp_excluded.matched_sids == [$sid] and .records[0].default.matched_sids == [$sid]
    end)
  ' "$report" >/dev/null; then
    pass_case "$label"
  else
    fail_case "$label" "rc=$rc output=$output"
  fi
}

run_role_plan_guard_contracts() {
  local guard fixture expected
  while IFS='|' read -r guard fixture expected; do
    run_plan_guard_case role-lane "$guard" "$fixture" "$expected"
  done <<'PLAN_GUARDS'
resources-array|plan-resources-object.json|FAIL: plan resources must be an array
exactly-one-document|plan-duplicate-document.json|FAIL: plan must contain exactly one aws_iam_role_policy.plan_reader_deny, found 2
nonempty-policy|plan-null-policy.json|FAIL: plan policy document is null, unknown, or empty: aws_iam_role_policy.plan_reader_deny
role-name|plan-null-role-name.json|FAIL: plan reader role name is null or unknown
suffix|plan-invalid-role-name.json|FAIL: cannot derive SUFFIX from plan reader role name: invalid-plan-reader
account-id-uniqueness|plan-multiple-account-ids.json|FAIL: plan policy documents contain multiple account ids:
PLAN_GUARDS
}



run_iam_simulate_role_lane_contracts() {
  local output rc mutated_inventory full_inventory full_scale role_lane_mutant
  local account account_mutant account_core_mutant account_report cleanup_mutant cleanup_report
  local mutant_inventory mutated_full_inventory mutation_fail mutation_output mutation_rc
  local fd_vectors only_case isolated_case duplicate_vectors
  local core_mutant expected_sid expected_hash_failure wrong_hash_report nonce_report fail_line
  local preflight_scope_mutant expected_scope_failure boundary_case authorization_report
  local wrong_mode_report wrong_mode_case_id expected_mode_failure
  local context_mutant plan_account_report plan_account_mutant_report trust_mutant
  local principal_mutant principal_report
  local per_pair_report role_decision_report trust_restored_report
  local propagation_report propagation_mutant allowed_case deny_case
  local authorization_case
  echo "== iam simulate contracts: ROLE-LANE =="
  group_failures=$failures

  if [ ! -x "$IAM_SIM_ROLE_LANE" ]; then
    fail_case "role-lane runner exists and is executable" "$IAM_SIM_ROLE_LANE is missing"
  else
    run_sid_contracts role-lane
    run_role_plan_guard_contracts

    if output="$(validate_readiness_inventory \
      "$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" 2>&1)"; then
      pass_case "role-lane full inventory has a readiness case for every projection"
    else
      fail_case "role-lane full inventory has a readiness case for every projection" "$output"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-account-foreign.json" \
      dispatch_registered_mutation \
        role-lane-plan-account-binding success --dry-run 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [ "$fail_line" = "FAIL: plan account mismatch: plan 222222222222, expected 000000000000" ] && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane plan account binding mutation -> $fail_line"
    else
      fail_case "role-lane plan account binding mutation did not fail before create" \
        "rc=$rc creates=$(phase2_call_count iam create-role) output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_TEST_ACCOUNT_ID=123456789012 \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-account-bound.json" \
      run_phase2_role_lane success --dry-run 2>&1)"; then
      pass_case "role-lane plan account binding mutation restored PASS"
    else
      fail_case "role-lane plan account binding mutation restoration" "$output"
    fi

    counter_core="$phase2_dir/iam-simulate-core-counter.py"
    core_call_log="$phase2_dir/core-calls.txt"
    instrument_core_counter "$counter_core"
    : >"$core_call_log"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_CORE="$counter_core" \
      IAM_SIM_TEST_CORE_CALL_LOG="$core_call_log" \
      IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       [ "$(grep -c '^map-role-pass$' "$core_call_log" || true)" -eq 2 ] && \
       ! grep -q '^map-response$' "$core_call_log"; then
      pass_case "role-lane maps all case results in one shared-core invocation per pass"
    else
      fail_case "role-lane maps all case results in one shared-core invocation per pass" \
        "rc=$rc calls=$(tr '\n' ',' <"$core_call_log") output=$output"
    fi

    run_role_shared_mapping_case \
      "deployer-position" \
      "role-lane maps real deployer_data delimiter-inclusive exclusive-end range" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      "$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      "$phase2_dir/role-deployer-position-custom-report.json" \
      "$phase2_dir/response-deployer-position.json" \
      "ClickhouseSecretCreateWithTag"
    for name in string-delimiters escaped-quotes; do
      expected_sid=DenyReadStateObjectsOutsideScope
      [ "$name" != escaped-quotes ] || expected_sid=DenyListBucketOutsideScope
      run_role_shared_mapping_case \
        "scanner-$name" \
        "role-lane scans exact statement spans with $name" \
        "$phase2_dir/plan-scanner-position.json" \
        "$phase2_dir/scanner-$name-vectors" \
        "$phase2_dir/role-scanner-$name-custom-report.json" \
        "$phase2_dir/response-scanner-$name.json" \
        "$expected_sid"
    done
    run_role_shared_mapping_case \
      "action-level" \
      "role-lane uses action-level decision when ResourceSpecificResults is absent" \
      "$phase2_plan" \
      "$phase2_dir/role-action-level-vectors" \
      "$phase2_dir/role-action-level-custom-report.json" \
      "$phase2_dir/response-role-action-level.json" \
      ""

    run_role_shared_mapping_case \
      "empty-resource" \
      "role-lane omits --resource-arns for an empty resource list" \
      "$phase2_plan" \
      "$phase2_dir/role-empty-resource-vectors" \
      "$phase2_dir/role-empty-resource-custom-report.json" \
      "$phase2_dir/response-role-action-level.json" \
      ""
    role_lane_mutant="$phase2_dir/iam-simulate-role-empty-resource-mutant.sh"
    dispatch_registered_mutation role-lane-empty-resource-list \
      "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
    IAM_SIM_TEST_ROLE_LANE="$role_lane_mutant" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-empty-resource-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-empty-resource-custom-report.json" \
      expect_role_failure \
        "role-lane empty resource list" \
        "fake simulate-principal-policy received --resource-arns with zero values" \
        success --only "$(jq -r '.records[0].case_id' \
          "$phase2_dir/role-empty-resource-custom-report.json")"

    authorization_report="$phase2_dir/role-authorization-split-report.json"
    authorization_case="case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_CORE="$phase2_authorization_core_mutant" \
      IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-authorization-split-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$authorization_report" \
      dispatch_registered_mutation role-lane-shared-authorization-partition \
        authorization-split --only "$authorization_case" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [[ "$fail_line" == "FAIL: SCP-excluded principal simulation failed for case:aws_iam_policy.deployer_data:EnvDataBucketLifecycle:ALL:none:matching: An error occurred (InvalidInput) when calling the SimulatePrincipalPolicy operation: Invalid Input Actions: "*" require different authorization information." ]]; then
      pass_case "role-lane shared authorization partition mutation -> $fail_line"
    else
      fail_case "role-lane shared authorization partition mutation did not fail as required" \
        "rc=$rc output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-authorization-split-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$authorization_report" \
      run_phase2_role_lane authorization-split --only "$authorization_case" 2>&1)" && \
       validate_role_authorization_split "$phase2_calls" "$authorization_report" \
         "$phase2_dir/authorization-split-vectors/authorization-split.json" && \
       ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane shared authorization partition mutation restored PASS (two calls per run; combined decisions)"
    else
      fail_case "role-lane shared authorization partition mutation restoration" "$output"
    fi

    core_mutant="$phase2_dir/iam-simulate-core-role-strict-containment.py"
    dispatch_registered_mutation role-lane-shared-core-unique-overlap \
      "$core_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_CORE="$core_mutant" \
      IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-deployer-position-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-shared-core-mutant-report.json" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-deployer-position.json" \
      run_phase2_role_lane success --only "case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: unmapped matched statement position from PolicyInputList.1' \
         <<<"$output"; then
      pass_case "role-lane shared-core unique-overlap mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane shared-core unique-overlap mutation did not fail as required" \
        "rc=$rc output=$output"
    fi
    run_role_shared_mapping_case \
      "shared-core-restored" \
      "role-lane shared-core mutation restored PASS" \
      "$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      "$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      "$phase2_dir/role-deployer-position-custom-report.json" \
      "$phase2_dir/response-deployer-position.json" \
      "ClickhouseSecretCreateWithTag"

    context_mutant="$phase2_dir/iam-simulate-roles-no-context.sh"
    dispatch_registered_mutation role-lane-principal-context-entry-preservation \
      "$IAM_SIM_ROLE_LANE" "$context_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_LANE="$context_mutant" \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-deployer-position-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-context-mutant-report.json" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-deployer-position.json" \
      run_phase2_role_lane context-required --only "case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 'FAIL: fake simulate-principal-policy context entries mismatch:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && [ -n "$fail_line" ]; then
      pass_case "role-lane principal context-entry preservation mutation -> $fail_line"
    else
      fail_case "role-lane principal context-entry preservation mutation did not fail" \
        "rc=$rc output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$REPO_ROOT/tests/fixtures/iam-matrix/base-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$REPO_ROOT/tests/fixtures/iam-simulate/vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-deployer-position-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-context-restored-report.json" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-deployer-position.json" \
      run_phase2_role_lane context-required --only "case:aws_iam_policy.deployer_data:ClickhouseSecretCreateWithTag:ALL:aws:RequestTag/Project:matching" 2>&1)"; then
      pass_case "role-lane principal context-entry preservation mutation restored PASS"
    else
      fail_case "role-lane principal context-entry preservation mutation restoration" "$output"
    fi

    trust_mutant="$phase2_dir/iam-simulate-roles-root-trust-mutant.sh"
    dispatch_registered_mutation role-lane-root-trust-refusal \
      "$IAM_SIM_ROLE_LANE" "$trust_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_LANE="$trust_mutant" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: temporary role trust must name exactly the invoking identity' <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane root trust refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane root trust refusal mutation did not fail before create-role" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi

    principal_mutant="$phase2_dir/iam-simulate-roles-principal-redaction-mutant.sh"
    principal_report="$phase2_dir/role-principal-redaction-mutant-report.json"
    dispatch_registered_mutation role-lane-caller-principal-report \
      "$IAM_SIM_ROLE_LANE" "$principal_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_LANE="$principal_mutant" \
      IAM_SIM_TEST_ROLE_REPORT="$principal_report" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: role report contains caller principal identity' <<<"$output"; then
      pass_case "role-lane caller-principal report mutation -> $(grep -m1 '^FAIL: role report contains caller principal identity' <<<"$output")"
    else
      fail_case "role-lane caller-principal report mutation did not fail in the writer" \
        "rc=$rc output=$output"
    fi

    trust_restored_report="$phase2_dir/role-exact-caller-restored-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_REPORT="$trust_restored_report" \
      run_phase2_role_lane success 2>&1)" && \
       validate_role_trust_calls "$phase2_calls" 000000000000 && \
       validate_role_principal_redaction "$trust_restored_report"; then
      pass_case "role-lane root trust refusal mutation restored PASS"
      pass_case "role-lane caller-principal report mutation restored PASS"
    else
      fail_case "role-lane exact-caller trust and principal redaction restoration" "$output"
    fi

    per_pair_report="$phase2_dir/role-per-pair-mutant-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/per-pair-sid-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-per-pair-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$per_pair_report" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-per-pair-sid-mutant.json" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && [ -f "$per_pair_report" ]; then
      expect_failure "role-lane per-pair required Sid" \
        "role comparison required matched Sid is absent for s3:GetObjectVersion *: DenyReadStateObjectsOutsideScope" \
        validate_role_per_pair "$per_pair_report"
    else
      fail_case "role-lane per-pair required Sid mutation setup" \
        "rc=$rc output=$output"
    fi

    per_pair_report="$phase2_dir/role-per-pair-restored-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/per-pair-sid-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-per-pair-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$per_pair_report" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-per-pair-sid-restored.json" \
      run_phase2_role_lane success 2>&1)" && \
       validate_role_per_pair "$per_pair_report"; then
      pass_case "role-lane per-pair required Sid mutation restored PASS"
    else
      fail_case "role-lane per-pair required Sid mutation restoration" "$output"
    fi

    role_decision_report="$phase2_dir/role-decision-mutant-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/per-pair-sid-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-per-pair-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$role_decision_report" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-per-pair-decision-mutant.json" \
      dispatch_registered_mutation role-lane-decision-expectation \
        success 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [ "$fail_line" = "FAIL: role lane recorded 1 case(s) that do not match vector expectations" ] && \
       jq -e '
         .summary.failed == 1
         and .records[0].pass == false
         and .records[0].scp_excluded.matches_expectation == false
         and any(.records[0].errors[]; contains("decision differs from expectation"))
       ' "$role_decision_report" >/dev/null; then
      pass_case "role-lane decision expectation mutation -> $fail_line"
    else
      fail_case "role-lane decision expectation mutation did not fail the lane" \
        "rc=$rc output=$output"
    fi

    per_pair_report="$phase2_dir/role-decision-restored-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-per-pair-sid.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/per-pair-sid-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-per-pair-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$per_pair_report" \
      IAM_SIM_TEST_PRINCIPAL_RESPONSE="$phase2_dir/response-per-pair-sid-restored.json" \
      run_phase2_role_lane success 2>&1)" && \
       validate_role_per_pair "$per_pair_report"; then
      pass_case "role-lane decision expectation mutation restored PASS"
    else
      fail_case "role-lane decision expectation mutation restoration" "$output"
    fi

    account=123456
    account+='789012'
    account_mutant="$phase2_dir/iam-simulate-roles-account-redaction-mutant.sh"
    account_core_mutant="$phase2_dir/iam-simulate-core-account-redaction-mutant.py"
    account_report="$phase2_dir/role-account-redaction-mutant-report.json"
    dispatch_registered_mutation role-lane-report-account-redaction \
      "$IAM_SIM_ROLE_LANE" "$account_mutant" \
      "$IAM_SIM_CORE" "$account_core_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ACCOUNT_ID="$account" \
      IAM_SIM_TEST_RUN_ID="fixture-$account" \
      IAM_SIM_TEST_CORE="$account_core_mutant" \
      IAM_SIM_TEST_ROLE_LANE="$account_mutant" \
      IAM_SIM_TEST_ROLE_REPORT="$account_report" \
      run_phase2_role_lane verify-present 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(validate_role_account_redaction \
      "$account_report" "$phase2_calls" "$account" 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -ne 0 ] && grep -Fq 'manual cleanup: role still exists' <<<"$output" && \
       [ "$mutation_rc" -ne 0 ] && \
       grep -Fq "FAIL: role report contains unredacted 12-digit account id: $account" <<<"$mutation_output"; then
      pass_case "role-lane report account redaction mutation -> $mutation_fail"
    else
      fail_case "role-lane report account redaction mutation did not fail as required" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi

    account_report="$phase2_dir/role-account-redaction-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ACCOUNT_ID="$account" \
      IAM_SIM_TEST_RUN_ID="fixture-$account" \
      IAM_SIM_TEST_ROLE_REPORT="$account_report" \
      run_phase2_role_lane verify-present 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'manual cleanup: role still exists' <<<"$output" && \
       validate_role_account_redaction "$account_report" "$phase2_calls" "$account"; then
      pass_case "role-lane report account redaction mutation restored PASS"
    else
      fail_case "role-lane report account redaction mutation restoration" \
        "rc=$rc output=$output"
    fi

    plan_account_report="$phase2_dir/role-plan-account-redaction-report.json"
    plan_account_mutant_report="$phase2_dir/role-plan-account-redaction-mutant-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources       IAM_SIM_TEST_ACCOUNT_ID="$account"       IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/plan-account-bound.json"       IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-plan-account-custom-report.json"       IAM_SIM_TEST_ROLE_REPORT="$plan_account_report"       run_phase2_role_lane success 2>&1)" &&        validate_role_plan_account_redaction "$plan_account_report" "$account" true; then
      dispatch_registered_mutation role-lane-plan-account-redaction         "$plan_account_report" "$plan_account_mutant_report" "$account"
      expect_failure "role-lane plan account redaction"         "role report contains unredacted plan account id: $account"         validate_role_plan_account_redaction           "$plan_account_mutant_report" "$account" true
    else
      fail_case "role-lane plan account redaction mutation setup" "$output"
    fi
    if validate_role_plan_account_redaction "$plan_account_report" "$account" true; then
      pass_case "role-lane plan account redaction mutation restored PASS"
    else
      fail_case "role-lane plan account redaction mutation restoration"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && validate_role_selection_report "$phase2_dir/role-report.json"; then
      pass_case "role-lane selects custom vectors and records custom-isolated exclusion"
      dispatch_registered_mutation role-lane-selection-reason \
        "$phase2_dir/role-report.json" "$phase2_dir/role-selection-mutant.json"
      expect_failure "role-lane selection reason" \
        "must record one custom-isolated exclusion with its reason" \
        validate_role_selection_report "$phase2_dir/role-selection-mutant.json"
      if validate_role_selection_report "$phase2_dir/role-report.json"; then
        pass_case "role-lane selection reason mutation restored PASS"
      else
        fail_case "role-lane selection reason mutation restoration"
      fi
    else
      fail_case "role-lane selects custom vectors and records custom-isolated exclusion" \
        "rc=$rc output=$output"
    fi

    boundary_case="case:aws_iam_policy.task_boundary:EcrAuth:ALL:none:outside-boundary"
    expected_scope_failure="FAIL: role lane cannot represent synthetic identity documents for $boundary_case: custom report submitted 2 policy_input_list documents"
    preflight_scope_mutant="$phase2_dir/iam-simulate-roles-preflight-scope-mutant.sh"
    dispatch_registered_mutation role-lane-excluded-custom-hash-preflight-scope \
      "$IAM_SIM_ROLE_LANE" "$preflight_scope_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_LANE="$preflight_scope_mutant" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && [ "$fail_line" = "$expected_scope_failure" ] && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane excluded custom hash preflight scope mutation -> $fail_line"
    else
      fail_case "role-lane excluded custom hash preflight scope mutation did not fail before create" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)" && \
       validate_role_selection_report "$phase2_dir/role-report.json"; then
      pass_case "role-lane excluded custom hash preflight scope mutation restored PASS"
    else
      fail_case "role-lane excluded custom hash preflight scope mutation restoration" "$output"
    fi

    only_case="case:aws_iam_role_policy.plan_reader_state:ReadStateObjects:ALL:none:matching"
    isolated_case="case:aws_iam_policy.deployer_data:LogsCreateWithTag:ALL:aws:RequestTag/Project:non-matching"
    reset_phase2_fake
    if output="$(run_phase2_role_lane success --dry-run --only "$only_case" 2>&1)" && \
       [ "$(grep -Ec 'iam simulate-principal-policy( |$)' <<<"$output" || true)" -eq 2 ]; then
      pass_case "role-lane --only exact id selects one supported case"
    else
      fail_case "role-lane --only exact id selects one supported case" "$output"
    fi
    role_lane_mutant="$phase2_dir/iam-simulate-roles-only-selection-mutant.sh"
    dispatch_registered_mutation role-lane-only-exact-id-selection \
      "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
    IAM_SIM_TEST_ROLE_LANE="$role_lane_mutant" expect_role_failure \
      "role-lane --only exact id selection" \
      "--only $only_case excluded: case id was not found" \
      success --dry-run --only "$only_case"
    reset_phase2_fake
    if output="$(run_phase2_role_lane success --dry-run --only "$only_case" 2>&1)" && \
       [ "$(grep -Ec 'iam simulate-principal-policy( |$)' <<<"$output" || true)" -eq 2 ]; then
      pass_case "role-lane --only exact id selection mutation restored PASS"
    else
      fail_case "role-lane --only exact id selection mutation restoration" "$output"
    fi
    expect_role_failure "role-lane --only missing id" \
      "--only case:fixture:missing excluded: case id was not found" \
      success --dry-run --only case:fixture:missing

    duplicate_vectors="$phase2_dir/role-only-duplicate-vectors"
    mkdir -p "$duplicate_vectors/nested"
    cp "$phase2_dir/role-vectors/role-0.json" "$duplicate_vectors/first.json"
    cp "$phase2_dir/role-vectors/role-0.json" "$duplicate_vectors/nested/second.json"
    IAM_SIM_TEST_ROLE_VECTORS="$duplicate_vectors" expect_role_failure \
      "role-lane --only duplicate id" \
      "--only $only_case excluded: duplicate exact case id (2 matches)" \
      success --dry-run --only "$only_case"
    expect_role_failure "role-lane --only unsupported id" \
      "--only $isolated_case excluded: isolated single-statement simulation has no principal equivalent" \
      success --dry-run --only "$isolated_case"

    reset_phase2_fake
    projection_report="$phase2_dir/role-projection-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$projection_report" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       validate_role_projection_report \
         "$projection_report" "$phase2_dir/role-projection-vectors" \
         "$phase2_dir/role-projection-plan.json" "$phase2_calls" && \
       [ "$(phase2_call_count iam create-role)" -eq 8 ] && \
       [ "$(phase2_call_count iam put-role-policy)" -eq 8 ] && \
       [ "$(phase2_call_count iam delete-role-policy)" -eq 8 ] && \
       [ "$(phase2_call_count iam delete-role)" -eq 8 ] && \
       [ "$(phase2_call_count iam get-role)" -eq 8 ]; then
      pass_case "role-lane projects fitting roles combined and deployer in six complete passes"
      dispatch_registered_mutation role-lane-projection-pass-count \
        "$projection_report" "$phase2_dir/role-projection-mutant.json"
      expect_failure "role-lane projection pass count" \
        "role projection requires eight passes" \
        validate_role_projection_report \
          "$phase2_dir/role-projection-mutant.json" \
          "$phase2_dir/role-projection-vectors" \
          "$phase2_dir/role-projection-plan.json" "$phase2_calls"
      if validate_role_projection_report \
        "$projection_report" "$phase2_dir/role-projection-vectors" \
        "$phase2_dir/role-projection-plan.json" "$phase2_calls"; then
        pass_case "role-lane projection pass count mutation restored PASS"
      else
        fail_case "role-lane projection pass count mutation restoration"
      fi
    else
      fail_case "role-lane projects fitting roles combined and deployer in six complete passes" \
        "rc=$rc output=$output"
    fi

    propagation_report="$phase2_dir/role-propagation-full-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$propagation_report" \
      run_phase2_role_lane propagation-delay 2>&1)" && \
       validate_role_projection_report \
         "$propagation_report" "$phase2_dir/role-projection-vectors" \
         "$phase2_dir/role-projection-plan.json" "$phase2_calls" 1; then
      pass_case "role-lane propagation full run retries readback and readiness probes"
    else
      fail_case "role-lane propagation full run retries readback and readiness probes" "$output"
    fi

    allowed_case="case:aws_iam_policy.deployer_data:EcrVerificationAuth:ALL:none:matching"
    propagation_report="$phase2_dir/role-propagation-allowed-only-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$propagation_report" \
      run_phase2_role_lane success --only "$allowed_case" 2>&1)" && \
       validate_role_propagation "$propagation_report" "$phase2_calls" \
         "$allowed_case" allowed - 1; then
      pass_case "role-lane propagation supports an allowed --only case"
    else
      fail_case "role-lane propagation supports an allowed --only case" "$output"
    fi
    if validate_role_propagation "$propagation_report" "$phase2_calls" \
      "$allowed_case" allowed \
      deployer:aws_iam_policy.deployer_guard 1 >/dev/null; then
      pass_case "role-lane propagation probes a zero-selected projection"
    else
      fail_case "role-lane propagation probes a zero-selected projection"
    fi

    deny_case="case:aws_iam_policy.deployer_guard:DenyMutatingOwnControlRoles:ALL:none:protected-resource"
    propagation_report="$phase2_dir/role-propagation-deny-only-report.json"
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$propagation_report" \
      run_phase2_role_lane success --only "$deny_case" 2>&1)" && \
       validate_role_propagation "$propagation_report" "$phase2_calls" \
         "$deny_case" explicitDeny - 1; then
      pass_case "role-lane propagation supports a deny-only --only case"
    else
      fail_case "role-lane propagation supports a deny-only --only case" "$output"
    fi

    propagation_report="$phase2_dir/role-propagation-readback-exhausted-report.json"
    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation \
      role-lane-readback-exhaustion-reason "$propagation_report" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'after 5 attempts: An error occurred (NoSuchEntity) when calling the GetRolePolicy operation' <<<"$output" && \
       validate_role_readback_exhaustion "$propagation_report" "$phase2_calls" && \
       ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
      pass_case "role-lane readback exhaustion reason mutation -> $fail_line"
    else
      fail_case "role-lane readback exhaustion reason mutation did not fail with the last error" \
        "rc=$rc output=$output"
    fi

    propagation_report="$phase2_dir/role-propagation-readiness-exhausted-report.json"
    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation \
      role-lane-readiness-exhaustion-reason "$propagation_report" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'after 5 attempts: FAIL: readiness decision does not match the selected case' <<<"$output" && \
       validate_role_readiness_exhaustion "$propagation_report" "$phase2_calls" && \
       ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
      pass_case "role-lane readiness exhaustion reason mutation -> $fail_line"
    else
      fail_case "role-lane readiness exhaustion reason mutation did not fail with the last reason" \
        "rc=$rc output=$output"
    fi

    propagation_mutant="$phase2_dir/iam-simulate-roles-propagation-retry-mutant.sh"
    dispatch_registered_mutation role-lane-propagation-retry \
      "$IAM_SIM_ROLE_LANE" "$propagation_mutant"
    IAM_SIM_TEST_ROLE_LANE="$propagation_mutant" \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-propagation-retry-mutant-report.json" \
      expect_role_failure \
        "role-lane propagation retry" \
        "inline policy readback propagation exhausted for" \
        propagation-delay
    if ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane propagation retry mutation cleanup restored PASS"
    else
      fail_case "role-lane propagation retry mutation cleanup restoration"
    fi

    while IFS='|' read -r source_mutation source_label source_failure; do
      role_lane_mutant="$phase2_dir/iam-simulate-roles-$source_mutation-mutant.sh"
      projection_report="$phase2_dir/role-source-$source_mutation-report.json"
      dispatch_registered_mutation "role-lane-source-$source_mutation" \
        "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
      reset_phase2_fake
      set +e
      output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
        IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
        IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
        IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
        IAM_SIM_TEST_ROLE_REPORT="$projection_report" \
        IAM_SIM_TEST_ROLE_LANE="$role_lane_mutant" \
        run_phase2_role_lane success 2>&1)"
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then
        expect_failure "$source_label" "$source_failure" \
          validate_role_projection_report \
            "$projection_report" "$phase2_dir/role-projection-vectors" \
            "$phase2_dir/role-projection-plan.json" "$phase2_calls"
      else
        fail_case "$source_label mutation setup" "rc=$rc output=$output"
      fi
    done <<'SOURCE_MUTATIONS'
partition|role-lane source partition|role projection plan-reader source order is
concatenation|role-lane source concatenation|role projection did not concatenate statements in source order
hash|role-lane source hash|role projection policy hash differs
SOURCE_MUTATIONS
    run_role_projection_restored_case "role-lane source mutations"

    wrong_hash_report="$phase2_dir/role-projection-wrong-hash-custom-report.json"
    expected_hash_failure="$(role_wrong_hash_expected_line \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" "$wrong_hash_report")"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$wrong_hash_report" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-projection-wrong-hash-report.json" \
      dispatch_registered_mutation role-lane-wrong-hash-preflight \
        success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fxq "$expected_hash_failure" <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane wrong-hash preflight mutation -> $expected_hash_failure"
    else
      fail_case "role-lane wrong-hash preflight mutation did not fail before create" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    wrong_mode_report="$phase2_dir/role-projection-wrong-mode-custom-report.json"
    wrong_mode_case_id="$(jq -r '.records[] | select(.mode == "principal") | .case_id' \
      "$wrong_mode_report")"
    expected_mode_failure="FAIL: custom report mode mismatch for $wrong_mode_case_id: report='principal' vector='custom'"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$wrong_mode_report" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-projection-wrong-mode-report.json" \
      dispatch_registered_mutation role-lane-wrong-mode-preflight \
        success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fxq "$expected_mode_failure" <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane wrong-mode preflight mutation -> $expected_mode_failure"
    else
      fail_case "role-lane wrong-mode preflight mutation did not fail before create" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    run_role_projection_restored_case "role-lane wrong-hash preflight"

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-duplicate-sid-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      dispatch_registered_mutation role-lane-duplicate-sid \
        success --dry-run 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq \
         'FAIL: duplicate Sid CrossDocumentDuplicate across aws_iam_role_policy.plan_reader_deny and aws_iam_role_policy.plan_reader_state' \
         <<<"$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane duplicate Sid mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane duplicate Sid mutation did not fail as required" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    if output="$(IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      run_phase2_role_lane success --dry-run 2>&1)" && \
       [ "$(grep -Ec 'iam create-role( |$)' <<<"$output" || true)" -eq 8 ]; then
      pass_case "role-lane duplicate Sid mutation restored projection passes"
    else
      fail_case "role-lane duplicate Sid mutation restored projection passes" "$output"
    fi

    reset_phase2_fake
    divergence_report="$phase2_dir/role-divergence-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-divergence-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$divergence_report" \
      run_phase2_role_lane success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && validate_role_divergence_report "$divergence_report"; then
      pass_case "role-lane records custom-lane divergence without failing"
      dispatch_registered_mutation role-lane-divergence-evidence \
        "$divergence_report" "$phase2_dir/role-divergence-mutant.json"
      expect_failure "role-lane divergence evidence" \
        "role divergence summary must contain two agreements and one divergence" \
        validate_role_divergence_report "$phase2_dir/role-divergence-mutant.json"
      if validate_role_divergence_report "$divergence_report"; then
        pass_case "role-lane divergence evidence mutation restored PASS"
      else
        fail_case "role-lane divergence evidence mutation restoration"
      fi
    else
      fail_case "role-lane records custom-lane divergence without failing" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-missing-custom-report.json" \
      dispatch_registered_mutation role-lane-missing-custom-case \
        success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: custom report lacks exactly one record for ' <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane missing custom case mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane missing custom case mutation did not fail before create as required" \
        "rc=$rc create_calls=$(phase2_call_count iam create-role) output=$output"
    fi
    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)"; then
      pass_case "role-lane missing custom case mutation restored complete report passes"
    else
      fail_case "role-lane missing custom case mutation restored complete report passes" "$output"
    fi

    reset_phase2_fake
    organizations_report="$phase2_dir/role-organizations-report.json"
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_REPORT="$organizations_report" \
      run_phase2_role_lane organizations-difference 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       validate_role_two_runs "$phase2_calls" "$organizations_report"; then
      pass_case "role-lane issues both runs and compares the scp-excluded result"
      dispatch_registered_mutation role-lane-two-run-call-shape \
        "$phase2_calls" "$phase2_dir/two-run-calls-mutant"
      expect_failure "role-lane two-run call shape" \
        "two-run contract requires one exact scp-excluded call and one default call per case" \
        validate_role_two_runs \
          "$phase2_dir/two-run-calls-mutant" "$organizations_report"
      if validate_role_two_runs "$phase2_calls" "$organizations_report"; then
        pass_case "role-lane two-run call shape mutation restored PASS"
      else
        fail_case "role-lane two-run call shape mutation restoration"
      fi
    else
      fail_case "role-lane issues both runs and compares the scp-excluded result" \
        "rc=$rc output=$output"
    fi

    reset_phase2_fake
    if output="$(run_phase2_role_lane success --dry-run 2>&1)" && \
       validate_dry_run_inventory "$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane dry-run prints the full inventory with zero calls"
    else
      fail_case "role-lane dry-run prints the full inventory with zero calls" "$output"
    fi
    mutated_inventory="$(dispatch_registered_mutation \
      role-lane-dry-run-inventory "$output")"
    expect_failure "role-lane dry-run inventory" "requires three iam delete-role-policy calls" \
      validate_dry_run_inventory "$mutated_inventory"

    full_inventory="$phase2_dir/full-fixture-dry-run.txt"
    reset_phase2_fake
    set +e
    output="$(run_full_scale_role_dry_run \
      "$IAM_SIM_ROLE_LANE" "$full_inventory" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && \
       full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane full-fixture dry-run terminates with formula count ($full_scale)"

      mutated_full_inventory="$phase2_dir/full-fixture-call-count-mutant.txt"
      dispatch_registered_mutation role-lane-full-fixture-formula-count \
        "$full_inventory" "$mutated_full_inventory"
      expect_failure "role-lane full-fixture formula count" \
        "full-fixture dry-run call count is" \
        validate_full_scale_role_dry_run "$mutated_full_inventory"
      if full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)"; then
        pass_case "role-lane full-fixture formula count mutation restored PASS ($full_scale)"
      else
        fail_case "role-lane full-fixture formula count mutation restoration" "$full_scale"
      fi

      role_lane_mutant="$phase2_dir/iam-simulate-roles-deterministic-fd-mutant.sh"
      dispatch_registered_mutation role-lane-portable-deterministic-descriptor-leak \
        "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
      mutant_inventory="$phase2_dir/reduced-fd-mutant-dry-run.txt"
      mutant_fd_samples="$phase2_dir/reduced-fd-mutant-samples.txt"
      fd_vectors="$phase2_dir/reduced-fd-vectors"
      prepare_fd_vectors "$fd_vectors"
      : >"$mutant_fd_samples"
      reset_phase2_fake
      set +e
      IAM_SIM_TEST_FD_SAMPLES="$mutant_fd_samples" \
        IAM_SIM_FULL_SCALE_VECTORS="$fd_vectors" \
        IAM_SIM_FULL_SCALE_TIMEOUT_SECONDS=5 \
        run_full_scale_role_dry_run \
          "$role_lane_mutant" "$mutant_inventory" >/dev/null 2>&1
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then
        expect_failure "role-lane portable deterministic descriptor leak" \
          "role-lane deterministic descriptor count grew by at least 1 per case" \
          validate_fd_leak_probe "$mutant_fd_samples"
      else
        fail_case "role-lane portable deterministic descriptor leak measurement" \
          "mutant run did not complete within 5 seconds: rc=$rc"
      fi

      role_lane_fd_probe="$phase2_dir/iam-simulate-roles-fd-probe.sh"
      real_fd_inventory="$phase2_dir/reduced-fd-real-dry-run.txt"
      real_fd_samples="$phase2_dir/reduced-fd-real-samples.txt"
      instrument_role_fd_reads "$IAM_SIM_ROLE_LANE" "$role_lane_fd_probe"
      : >"$real_fd_samples"
      reset_phase2_fake
      if IAM_SIM_TEST_FD_SAMPLES="$real_fd_samples" \
           IAM_SIM_FULL_SCALE_VECTORS="$fd_vectors" \
           IAM_SIM_FULL_SCALE_TIMEOUT_SECONDS=5 \
           run_full_scale_role_dry_run \
             "$role_lane_fd_probe" "$real_fd_inventory" >/dev/null 2>&1 && \
         fd_stability="$(validate_fd_stability_probe "$real_fd_samples" 2>&1)" && \
         [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
        pass_case "role-lane real-lane FD stability ($fd_stability)"
      else
        fail_case "role-lane real-lane FD stability" \
          "${fd_stability:-validation did not run}"
      fi

      reset_phase2_fake
      if run_full_scale_role_dry_run \
           "$IAM_SIM_ROLE_LANE" "$full_inventory" >/dev/null 2>&1 && \
         full_scale="$(validate_full_scale_role_dry_run "$full_inventory" 2>&1)" && \
         [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
        pass_case "role-lane portable deterministic descriptor leak mutation restored PASS ($full_scale)"
      else
        fail_case "role-lane portable deterministic descriptor leak mutation restoration" \
          "${full_scale:-validation did not run}"
      fi
    else
      fail_case "role-lane full-fixture dry-run terminates with formula count" \
        "rc=$rc emitted_calls=$(grep -c '^DRY-RUN:' "$full_inventory" 2>/dev/null || true) output=$output"
    fi

    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation \
      role-lane-opt-in-refusal success 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'FAIL: IAM_SIM_LANE_CONFIRM must equal create-real-iam-resources' <<<"$output" && \
       [ "$(find "$phase2_calls" -name '*.json' -type f | wc -l | tr -d ' ')" -eq 0 ]; then
      pass_case "role-lane opt-in refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane opt-in refusal mutation did not fail as required" "$output"
    fi

    reset_phase2_fake
    set +e
    output="$(dispatch_registered_mutation \
      role-lane-account-mismatch-refusal 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq 'FAIL: caller account mismatch' <<<"$output" && \
       [ "$(phase2_call_count iam create-role)" -eq 0 ]; then
      pass_case "role-lane account mismatch refusal mutation -> $(grep -m1 '^FAIL:' <<<"$output")"
    else
      fail_case "role-lane account mismatch refusal mutation did not fail as required" "$output"
    fi

    expect_role_failure "role-lane tag mismatch pre-mutation refusal" "ownership tag mismatch" tag-mismatch
    if [ "$(phase2_call_count iam put-role-policy)" -ne 0 ] || \
       [ "$(phase2_call_count iam delete-role)" -ne 0 ]; then
      fail_case "role-lane tag mismatch pre-mutation refusal" "a mutation ran after tag mismatch"
    fi

    nonce_report="$phase2_dir/role-nonce-tamper-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$nonce_report" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      dispatch_registered_mutation role-lane-nonce-tamper-at-deployer-p4 \
        nonce-tamper 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       grep -Fq 'FAIL: ownership tag mismatch for orbit-iam-sim-fixture-run-deployer-p4' \
         <<<"$output" && \
       validate_role_nonce_tamper "$nonce_report" "$phase2_calls" "$phase2_roles"; then
      pass_case "role-lane nonce tamper at deployer p4 mutation -> $fail_line"
    else
      fail_case "role-lane nonce tamper at deployer p4 mutation did not fail closed" \
        "rc=$rc output=$output"
    fi
    role_lane_mutant="$phase2_dir/iam-simulate-roles-nonce-ignoring-mutant.sh"
    dispatch_registered_mutation role-lane-nonce-ignoring-mutant \
      "$IAM_SIM_ROLE_LANE" "$role_lane_mutant"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$phase2_dir/role-nonce-mutant-report.json" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      IAM_SIM_TEST_ROLE_LANE="$role_lane_mutant" \
      run_phase2_role_lane nonce-tamper 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(validate_role_nonce_tamper \
      "$phase2_dir/role-nonce-mutant-report.json" \
      "$phase2_calls" "$phase2_roles" 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -eq 0 ] && [ "$mutation_rc" -ne 0 ] && \
       grep -Fq 'FAIL: nonce tamper reached policy or role mutations:' \
         <<<"$mutation_output"; then
      pass_case "role-lane nonce-ignoring mutant -> $mutation_fail"
    else
      fail_case "role-lane nonce-ignoring mutant was not killed" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi

    nonce_report="$phase2_dir/role-nonce-tamper-restored-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$nonce_report" \
      IAM_SIM_TEST_ROLE_INJECTION_SUFFIX=-deployer-p4 \
      run_phase2_role_lane nonce-tamper 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && validate_role_nonce_tamper \
      "$nonce_report" "$phase2_calls" "$phase2_roles"; then
      pass_case "role-lane nonce-ignoring mutant restored PASS"
    else
      fail_case "role-lane nonce-ignoring mutant restoration" "rc=$rc output=$output"
    fi
    run_role_projection_restored_case "role-lane nonce tamper"

    expect_role_failure "role-lane EntityAlreadyExists isolation" "manual cleanup: role already existed at create time" entity-exists
    if [ "$(phase2_call_count iam delete-role-policy)" -ne 0 ] || \
       [ "$(phase2_call_count iam delete-role)" -ne 0 ]; then
      fail_case "role-lane EntityAlreadyExists isolation" "collision caused a delete"
    fi

    run_registered_role_creation_failure_case \
      "role-lane midway create cleanup (3 roles)" create-midway "create-role failed" \
      3 2 1 "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json"
    run_registered_role_creation_failure_case \
      "role-lane midway create cleanup (8 roles at deployer p4)" \
      create-midway "create-role failed" 8 5 4 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

    cleanup_mutant="$phase2_dir/iam-simulate-roles-high-index-cleanup-mutant.sh"
    dispatch_registered_mutation \
      role-lane-high-index-cleanup-mutation-retains-3-role-pass \
      "$IAM_SIM_ROLE_LANE" "$cleanup_mutant"
    run_registered_role_creation_failure_case \
      "role-lane high-index cleanup mutation retains 3-role PASS" \
      create-midway "create-role failed" 3 2 1 \
      "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json" "$cleanup_mutant"

    cleanup_report="$phase2_dir/role-high-index-cleanup-mutant-report.json"
    reset_phase2_fake
    set +e
    output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      IAM_SIM_TEST_ROLE_PLAN="$phase2_dir/role-projection-plan.json" \
      IAM_SIM_TEST_ROLE_VECTORS="$phase2_dir/role-projection-vectors" \
      IAM_SIM_TEST_ROLE_CUSTOM_REPORT="$phase2_dir/role-projection-custom-report.json" \
      IAM_SIM_TEST_ROLE_REPORT="$cleanup_report" \
      IAM_SIM_TEST_ROLE_FAILURE_CREATE_INDEX=5 \
      IAM_SIM_TEST_ROLE_LANE="$cleanup_mutant" \
      run_phase2_role_lane create-midway 2>&1)"
    rc=$?
    set -e
    set +e
    mutation_output="$(dispatch_registered_mutation \
      role-lane-high-index-cleanup-8-role \
      "$cleanup_report" "$phase2_calls" 8 5 4 2>&1)"
    mutation_rc=$?
    set -e
    mutation_fail="$(grep -m1 '^FAIL:' <<<"$mutation_output" || true)"
    if [ "$rc" -ne 0 ] && grep -Fq 'create-role failed' <<<"$output" && \
       [ "$mutation_rc" -ne 0 ] && \
       grep -Fq 'FAIL: role failure cleanup did not delete every created role in reverse order' \
         <<<"$mutation_output" && \
       find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane high-index cleanup 8-role mutation -> $mutation_fail"
    else
      fail_case "role-lane high-index cleanup 8-role mutation did not fail as required" \
        "runner_rc=$rc validation_rc=$mutation_rc runner=$output validation=$mutation_output"
    fi
    run_registered_role_creation_failure_case \
      "role-lane high-index cleanup mutation restored 8-role PASS" \
      create-midway "create-role failed" 8 5 4 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

    expect_role_failure "role-lane delete-policy barrier" "manual cleanup: delete-role-policy failed" delete-policy-fails
    if python3 - "$phase2_calls" <<'PY'
import json
from pathlib import Path
import sys
calls = [json.loads(path.read_text()) for path in sorted(Path(sys.argv[1]).glob("*.json"), key=lambda path: int(path.stem))]
failed_role = next(call[call.index("--role-name") + 1] for call in calls if call[:2] == ["iam", "delete-role-policy"])
raise SystemExit(any(call[:2] == ["iam", "delete-role"] and call[call.index("--role-name") + 1] == failed_role for call in calls))
PY
    then
      :
    else
      fail_case "role-lane delete-policy barrier" "role delete followed the failed policy delete"
    fi

    run_registered_role_creation_failure_case \
      "role-lane TERM cleanup (3 roles)" term-during-create "terminated by TERM" \
      3 1 1 "$phase2_plan" "$phase2_dir/role-vectors" \
      "$phase2_dir/role-custom-report.json"
    run_registered_role_creation_failure_case \
      "role-lane TERM cleanup (8 roles at deployer p4)" \
      term-during-create "terminated by TERM" 8 5 5 \
      "$phase2_dir/role-projection-plan.json" \
      "$phase2_dir/role-projection-vectors" \
      "$phase2_dir/role-projection-custom-report.json"

    run_registered_role_cleanup_race_case \
      "role-lane TERM between put and marker (8 roles at deployer p4)" \
      term-during-put 143 "FAIL: terminated by TERM"
    run_role_projection_restored_case "role-lane TERM between put and marker"

    run_registered_role_cleanup_race_case \
      "role-lane unattached-policy NoSuchEntity cleanup (8 roles at deployer p4)" \
      put-policy-fails 1 \
      "FAIL: put-role-policy failed for orbit-iam-sim-fixture-run-deployer-p4"
    run_role_projection_restored_case "role-lane unattached-policy NoSuchEntity cleanup"

    run_registered_role_cleanup_race_case \
      "role-lane deferred TERM after delete-role-policy (8 roles at deployer p4)" \
      term-after-delete-policy 143 "FAIL: terminated by TERM"
    run_role_projection_restored_case "role-lane deferred TERM after delete-role-policy"

    reset_phase2_fake
    if output="$(IAM_SIM_LANE_CONFIRM=create-real-iam-resources \
      run_phase2_role_lane success 2>&1)" && \
       [ "$(phase2_call_count iam get-role)" -eq 3 ] && \
       ! find "$phase2_roles" -name '*.json' -type f | grep -q .; then
      pass_case "role-lane verifies NoSuchEntity after cleanup"
    else
      fail_case "role-lane verifies NoSuchEntity after cleanup" "$output"
    fi
    expect_role_failure "role-lane post-cleanup verification" "manual cleanup: role still exists" verify-present
  fi

  if [ "$failures" -eq "$group_failures" ]; then
    echo "PASS: IAM simulate ROLE-LANE group"
  else
    echo "FAIL: IAM simulate ROLE-LANE group" >&2
  fi
}


mutate_report_writer() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-report-writer "$@"
}

mutate_report_temp_directory() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-report-temp-directory "$@"
}

mutate_report_redaction() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-report-redaction "$@"
}

mutate_renderer_role_outcome() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-renderer-role-outcome \
    "$1" "$2" "$submode" "$3"
}

mutate_renderer_role_expectation() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-renderer-role-expectation \
    "$1" "$2" "$submode"
}

mutate_role_empty_resources() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-role-empty-resources \
    "$1" "$2" "$REPO_ROOT"
}

mutate_artifact_hygiene_field_scope() {
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-artifact-hygiene-field-scope "$@"
}

mutate_provenance_digest() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-provenance-digest "$@" "$submode"
}

mutate_evidence_hash_chain() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-evidence-hash-chain "$@" "$submode"
}

mutate_renderer_recording() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-renderer-recording "$@" "$submode"
}

run_renderer_recorded_on_modern() {
  "$IAM_SIM_REPORT_RENDERER" \
    --custom-report "$1" --role-report "$2" --recorded-on 2026-09-10 \
    --out-dir "$3"
}

run_renderer_date_refusal() {
  local submode=$1 renderer=$2 custom_report=$3 role_report=$4 out_dir=$5
  local mixed_custom="$phase2_dir/renderer-mixed-modern-custom.json"
  case "$submode" in
    mixed)
      jq '.recorded_at = "2026-09-10T00:00:00Z"' \
        "$custom_report" >"$mixed_custom"
      IAM_SIM_REPORT_REPO_ROOT="$REPO_ROOT" "$renderer" \
        --custom-report "$mixed_custom" --role-report "$role_report" \
        --out-dir "$out_dir"
      ;;
    missing)
      IAM_SIM_REPORT_REPO_ROOT="$REPO_ROOT" "$renderer" \
        --custom-report "$custom_report" --out-dir "$out_dir"
      ;;
    malformed)
      IAM_SIM_REPORT_REPO_ROOT="$REPO_ROOT" "$renderer" \
        --custom-report "$custom_report" --recorded-on 2026/09/10 \
        --out-dir "$out_dir"
      ;;
    *) echo "FAIL: unknown renderer date refusal mutation: $submode" >&2; return 1 ;;
  esac
}

mutate_generator_commit() {
  local submode=$1
  shift
  python3 "$IAM_SIM_FIXTURE_FACTORY" mutate-generator-commit \
    "$1" "$2" "$submode" "$REPO_ROOT" "${@:3}"
}

mutate_report_renderer() {
  local mutation=$1 output=$2
  python3 - "$IAM_SIM_REPORT_RENDERER" "$output" "$mutation" <<'PY'
from pathlib import Path
import sys

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
mutation = sys.argv[3]
source = source_path.read_text(encoding="utf-8")
replacements = {
    "hygiene": (
        'if ! "$HYGIENE" "${hygiene_inputs[@]}"; then  # artifact-hygiene-publication-guard',
        'if false; then  # artifact-hygiene-publication-guard',
    ),
    "json-hygiene": (
        'hygiene_inputs=("$custom_report")',
        'hygiene_inputs=()',
    ),
    "role-redaction": (
        'if report.get("account_redacted") is not True:  # role-account-redacted-guard',
        'if False:  # role-account-redacted-guard',
    ),
    "publication": (
        'mv -- "$rendered_report" "$out_dir/IAM_SIMULATION_REPORT.md"',
        'mv -- "$rendered_report" "$out_dir/IAM_SIMULATION_REPORT.md"\necho "FAIL: injected publication failure between report and provenance" >&2\nfalse',
    ),
    "resource-decisions": (
        '    per_resource = expectation.get("resource_decisions")',
        '    per_resource = None',
    ),
    "scalar-resource-decisions": (
        '        if isinstance(details, list):  # resource-decision-details-guard',
        '        if not isinstance(observed, dict) or not observed:\n            return False\n        if isinstance(details, list):  # resource-decision-details-guard',
    ),
    "doctored-pass": (
        "        if matches(record):",
        '        if record.get("pass"):',
    ),
}
old, new = replacements[mutation]
if source.count(old) != 1:
    raise SystemExit(
        f"FAIL: renderer mutation anchor count for {mutation} is "
        f"{source.count(old)}, expected 1"
    )
output_path.write_text(source.replace(old, new), encoding="utf-8")
PY
  chmod +x "$output"
}

validate_renderer_doctored_pass() {
  local renderer=$1 custom_report=$2 out_dir=$3 case_id=$4
  run_report_renderer "$renderer" "$custom_report" "" "$out_dir"
  python3 - "$out_dir/IAM_SIMULATION_REPORT.md" "$case_id" <<'PY'
from pathlib import Path
import sys

report = Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    findings = report.split("## Findings", 1)[1].split("## Divergences", 1)[0]
except IndexError:
    raise SystemExit("FAIL: rendered report lacks a bounded Findings section") from None
if sys.argv[2] not in findings:
    raise SystemExit(f"FAIL: doctored pass suppressed renderer finding: {sys.argv[2]}")
PY
}

run_report_renderer() {
  local renderer=$1 custom_report=$2 role_report=$3 out_dir=$4
  local -a args=(--custom-report "$custom_report" --out-dir "$out_dir")
  if [ -n "$role_report" ]; then
    args+=(--role-report "$role_report")
  fi
  if ! jq -e 'has("recorded_at")' "$custom_report" >/dev/null; then
    args+=(--recorded-on 2026-09-10)
  fi
  IAM_SIM_REPORT_REPO_ROOT="$REPO_ROOT" "$renderer" "${args[@]}"
}

validate_rendered_iam_reports() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

report = Path(sys.argv[1]).read_text(encoding="utf-8")
provenance = Path(sys.argv[2]).read_text(encoding="utf-8")
required_report = (
    "| Case ID | Mode | Expected | Observed | Matched Sids | Pass |",
    "## Findings",
    "| recorded_on |",
    "| generator commit |",
    "case:fixture.policy:DenyRead:ALL:none:non-matching",
    "Expected: `allowed`; observed: `explicitDeny`.",
    "## Divergences",
    "| Case ID | Scope | Expected | Custom observed | SCP-excluded | Default |",
    "| case:fixture.policy:DenyRead:ALL:none:non-matching | principal/custom | allowed | explicitDeny | allowed | explicitDeny |",
    "| custom | 2 | 1 | 1 | 0 |",
    "| role | 2 | 2 | 0 | 0 |",
    "## Submitted document SHA-256s",
    "000000000000",
)
required_provenance = (
    "| recorded_from |",
    "| recorded_on |",
    "| generator commit |",
    "| commands |",
    "Free Plan account in `us-east-1`",
    "## Exclusions",
    "isolated single-statement simulation has no principal equivalent",
    "## Hygiene review (what was actually checked)",
    "000000000000",
)
missing = [value for value in required_report if value not in report]
missing += [value for value in required_provenance if value not in provenance]
if missing:
    raise SystemExit(
        "FAIL: rendered IAM simulation artifacts omit required content: "
        f"{missing[0]}"
    )
print(
    "PASS: rendered IAM simulation artifacts contain the required report "
    "and provenance sections"
)
PY
}

validate_renderer_mixed_resource_decisions() {
  local report=$1
  local case_id=case:fixture.policy:MixedRead:ALL:none:mixed
  if ! grep -Fq "| $case_id | custom | explicitDeny |" "$report" || \
     ! grep -F "| $case_id |" "$report" | grep -Fq '| yes |'; then
    echo "FAIL: matching resource_decisions rendered as a failure" >&2
    return 1
  fi
}


validate_renderer_summary_counts() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
from pathlib import Path
import re
import sys


custom_path, role_path, rendered_path = map(Path, sys.argv[1:])
rendered = rendered_path.read_text(encoding="utf-8")
rendered_counts = {
    match.group(1): {
        "total": int(match.group(2)),
        "passed": int(match.group(3)),
        "failed": int(match.group(4)),
        "runner_failures": int(match.group(5)),
    }
    for match in re.finditer(
        r"^\| (custom|role) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|$",
        rendered,
        re.MULTILINE,
    )
}
for lane, report_path in (("custom", custom_path), ("role", role_path)):
    summary = json.loads(report_path.read_text(encoding="utf-8")).get("summary")
    required = ("total", "passed", "failed")
    if not isinstance(summary, dict) or any(key not in summary for key in required):
        raise SystemExit(f"FAIL: committed {lane} JSON summary lacks outcome counts")
    expected = {key: summary[key] for key in required}
    if "runner_failures" in summary:
        expected["runner_failures"] = summary["runner_failures"]
    actual = {
        key: rendered_counts.get(lane, {}).get(key)
        for key in expected
    }
    if actual != expected:
        raise SystemExit(
            f"FAIL: rendered {lane} counts differ from JSON summary: "
            f"rendered={actual} json={expected}"
        )
print("PASS: rendered IAM simulation counts equal both committed JSON summaries")
PY
}


run_iam_simulate_report_contracts() {
  local group_failures=$failures
  local clean_custom="$IAM_SIM_REPORT_FIXTURES/iam-simulation-custom-report.json"
  local clean_role="$IAM_SIM_REPORT_FIXTURES/iam-simulation-role-report.json"
  local report_name="IAM_SIMULATION_REPORT.md"
  local provenance_name="IAM_SIMULATION_PROVENANCE.md"
  local clean_out="$phase2_dir/rendered-clean"
  local hash_custom="$phase2_dir/custom-report-hash-account-id.json"
  local hash_out="$phase2_dir/rendered-hash"
  local bad_case_custom="$phase2_dir/custom-report-case-account-id.json"
  local bad_case_out="$phase2_dir/rendered-bad-case"
  local bad_json_custom="$IAM_SIM_REPORT_FIXTURES/bad-iam-simulation-report.json"
  local bad_json_out="$phase2_dir/rendered-bad-json"
  local unmarked_role="$phase2_dir/role-report-without-account-redacted.json"
  local unmarked_out="$phase2_dir/rendered-unmarked-role"
  local compact_report="$phase2_dir/compact-writer-report.json"
  local compact_writer_mutant="$phase2_dir/iam-simulate-core-pretty-report.py"
  local redaction_writer_mutant="$phase2_dir/iam-simulate-core-no-redaction.py"
  local principal_redaction_mutant="$phase2_dir/iam-simulate-core-principal-redaction-mutant.py"
  local principal_redaction_report="$phase2_dir/principal-redaction-report.json"
  local hygiene_principal_mutant="$phase2_dir/artifact-hygiene-principal-mutant.sh"
  local bad_principal_fixture="$IAM_SIM_REPORT_FIXTURES/bad-principal-arn.md"
  local hygiene_request_case_mutant="$phase2_dir/artifact-hygiene-request-case-mutant.sh"
  local bad_lowercase_request_fixture="$IAM_SIM_REPORT_FIXTURES/bad-request-id-lowercase.md"
  local atomic_writer_mutant="$phase2_dir/iam-simulate-core-cross-directory.py"
  local role_expectation_mismatch="$phase2_dir/role-expectation-mismatch.json"
  local role_expectation_out="$phase2_dir/rendered-role-expectation-mismatch"
  local mixed_custom="$phase2_dir/mixed-resource-decisions.json"
  local mixed_mutant="$phase2_dir/iam-simulate-report-scalar-only.sh"
  local mixed_mutant_out="$phase2_dir/rendered-mixed-mutant"
  local mixed_restored_out="$phase2_dir/rendered-mixed-restored"
  local evidence_out="$phase2_dir/rendered-evidence-counts"
  local scalar_rejection_mutant="$phase2_dir/iam-simulate-report-scalar-rejection.sh"
  local scalar_rejection_out="$phase2_dir/rendered-scalar-rejection"
  local scalar_restored_out="$phase2_dir/rendered-scalar-restored"
  local failed_case="case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching"
  local doctored_pass_custom="$phase2_dir/doctored-pass-custom-report.json"
  local doctored_pass_out="$phase2_dir/rendered-doctored-pass"
  local doctored_pass_renderer="$phase2_dir/iam-simulate-report-doctored-pass.sh"
  local publication_mutant="$phase2_dir/iam-simulate-report-publication-mutant.sh"
  local publication_out="$phase2_dir/rendered-publication-transaction"
  local json_hygiene_mutant="$phase2_dir/iam-simulate-report-no-json-hygiene.sh"
  local json_hygiene_mutant_out="$phase2_dir/rendered-json-hygiene-mutant"
  local output rc fail_line checker_output case_fold_anchor case_fold_anchor_count
  local role_outcome role_outcome_case role_outcome_report role_outcome_out
  local structural_diagnostic expectation_mutation expectation_report
  local expectation_label expectation_diagnostic date_case date_label date_diagnostic
  local bad_field_hex="$phase2_dir/bad-nondigest-hex.json"
  local field_scope_mutant="$phase2_dir/artifact-hygiene-field-scope-mutant.sh"

  if output="$(
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-atomic-replace \
      "$IAM_SIM_CORE" "$phase2_dir/atomic-report/output/report.json" \
      "$phase2_dir/atomic-report/external-scratch" 2>&1
  )"; then
    pass_case "shared report writer uses a destination-directory atomic replacement"
  else
    fail_case "shared report writer destination-directory atomic replacement" "$output"
  fi

  dispatch_registered_mutation report-destination-directory-atomic-replacement \
    "$IAM_SIM_CORE" "$atomic_writer_mutant"
  expect_failure "report destination-directory atomic replacement" \
    "shared report writer attempted cross-directory replacement" \
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-atomic-replace \
      "$atomic_writer_mutant" "$phase2_dir/atomic-mutant/output/report.json" \
      "$phase2_dir/atomic-mutant/external-scratch"
  if output="$(
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-atomic-replace \
      "$IAM_SIM_CORE" "$phase2_dir/atomic-restored/output/report.json" \
      "$phase2_dir/atomic-restored/external-scratch" 2>&1
  )"; then
    pass_case "report destination-directory atomic replacement mutation restored PASS"
  else
    fail_case "report destination-directory atomic replacement mutation restoration" "$output"
  fi

  if output="$(
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-writer \
      "$IAM_SIM_CORE" "$compact_report" 2>&1
  )"; then
    pass_case "shared report writer preserves JSON content and compact sorted record lines"
  else
    fail_case "shared report writer compact rendering" "$output"
  fi

  dispatch_registered_mutation report-whole-object-redaction \
    "$IAM_SIM_CORE" "$redaction_writer_mutant"
  expect_failure "report whole-object redaction" \
    "shared report writer retained live identifiers" \
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-writer \
      "$redaction_writer_mutant" "$compact_report"
  if output="$(
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-writer \
      "$IAM_SIM_CORE" "$compact_report" 2>&1
  )"; then
    pass_case "report whole-object redaction mutation restored PASS"
  else
    fail_case "report whole-object redaction mutation restoration" "$output"
  fi

  if output="$(validate_report_principal_redaction \
    "$IAM_SIM_CORE" "$principal_redaction_report" 2>&1)"; then
    pass_case "shared report writer fully redacts principal identity paths"
  else
    fail_case "shared report writer principal identity-path redaction" "$output"
  fi
  dispatch_registered_mutation report-principal-path-redaction \
    "$IAM_SIM_CORE" "$principal_redaction_mutant"
  expect_failure "report principal path redaction" \
    "shared report writer retained principal identity path" \
    validate_report_principal_redaction \
      "$principal_redaction_mutant" "$principal_redaction_report"
  if output="$(validate_report_principal_redaction \
    "$IAM_SIM_CORE" "$principal_redaction_report" 2>&1)"; then
    pass_case "report principal path redaction mutation restored PASS"
  else
    fail_case "report principal path redaction mutation restoration" "$output"
  fi

  set +e
  output="$(bash "$IAM_SIM_ARTIFACT_HYGIENE" "$bad_principal_fixture" 2>&1)"
  rc=$?
  set -e
  fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
  if [ "$rc" -ne 0 ] && grep -Fq ': principal-arn -' <<<"$fail_line"; then
    pass_case "artifact hygiene rejects an unredacted principal ARN"
  else
    fail_case "artifact hygiene unredacted principal ARN refusal" \
      "rc=$rc output=$output"
  fi
  dispatch_registered_mutation artifact-hygiene-principal-arn-guard \
    "$IAM_SIM_ARTIFACT_HYGIENE" "$hygiene_principal_mutant"
  # shellcheck disable=SC2016
  expect_failure "artifact hygiene principal ARN guard" \
    "artifact hygiene principal ARN guard mutant accepted an identity path" \
    bash -c '
      if bash "$1" "$2" >/dev/null 2>&1; then
        echo "FAIL: artifact hygiene principal ARN guard mutant accepted an identity path" >&2
        exit 1
      fi
    ' _ "$hygiene_principal_mutant" "$bad_principal_fixture"
  set +e
  output="$(bash "$IAM_SIM_ARTIFACT_HYGIENE" "$bad_principal_fixture" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && grep -Fq ': principal-arn -' <<<"$output"; then
    pass_case "artifact hygiene principal ARN guard mutation restored PASS"
  else
    fail_case "artifact hygiene principal ARN guard mutation restoration" \
      "rc=$rc output=$output"
  fi

  case_fold_anchor='REQUEST_ID_KEY = re.compile(r"(?:x-amzn-)?RequestId", re.IGNORECASE)'
  case_fold_anchor_count="$(grep -Fxc "$case_fold_anchor" "$IAM_SIM_ARTIFACT_HYGIENE" || true)"
  if [ "$case_fold_anchor_count" -ne 1 ]; then
    fail_case "artifact hygiene request ID case-folding mutation setup" \
      "anchor count=$case_fold_anchor_count"
  else
    dispatch_registered_mutation artifact-hygiene-request-id-case-folding \
      "$IAM_SIM_ARTIFACT_HYGIENE" "$hygiene_request_case_mutant"
    # shellcheck disable=SC2016
    expect_failure "artifact hygiene request ID case folding" \
      "artifact hygiene request ID case-folding mutant accepted lowercase requestid" \
      bash -c '
        if bash "$1" "$2" >/dev/null 2>&1; then
          echo "FAIL: artifact hygiene request ID case-folding mutant accepted lowercase requestid" >&2
          exit 1
        fi
      ' _ "$hygiene_request_case_mutant" "$bad_lowercase_request_fixture"
    set +e
    output="$(bash "$IAM_SIM_ARTIFACT_HYGIENE" "$bad_lowercase_request_fixture" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] && grep -Fq ': request-id -' <<<"$output"; then
      pass_case "artifact hygiene request ID case folding mutation restored PASS"
    else
      fail_case "artifact hygiene request ID case folding mutation restoration" \
        "rc=$rc output=$output"
    fi
  fi

  dispatch_registered_mutation report-compact-writer \
    "$IAM_SIM_CORE" "$compact_writer_mutant"
  expect_failure "report compact writer" \
    "compact report records must contain exactly one record per line" \
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-writer \
      "$compact_writer_mutant" "$compact_report"
  if output="$(
    python3 "$IAM_SIM_FIXTURE_FACTORY" validate-report-writer \
      "$IAM_SIM_CORE" "$compact_report" 2>&1
  )"; then
    pass_case "report compact writer mutation restored PASS"
  else
    fail_case "report compact writer mutation restoration" "$output"
  fi


  python3 - "$bad_field_hex" <<'PY_FIELD_HEX'
import json
from pathlib import Path
import sys

value = ("a" * 10) + ("1" * 12) + ("b" * 42)
Path(sys.argv[1]).write_text(json.dumps({"payload": value}) + "\n", encoding="utf-8")
PY_FIELD_HEX
  set +e
  output="$(bash "$IAM_SIM_ARTIFACT_HYGIENE" "$bad_field_hex" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && grep -Fq ': account-id -' <<<"$output"; then
    pass_case "artifact hygiene field-scoped hex rejects a non-digest JSON value"
  else
    fail_case "artifact hygiene field-scoped hex rejection" "rc=$rc output=$output"
  fi
  dispatch_registered_mutation artifact-hygiene-field-scoped-hex \
    "$IAM_SIM_ARTIFACT_HYGIENE" "$field_scope_mutant"
  if output="$(bash "$field_scope_mutant" "$bad_field_hex" 2>&1)" && \
     grep -q '^PASS:' <<<"$output"; then
    pass_case "artifact hygiene field scoped hex mutation -> FAIL: artifact hygiene field-scoped hex mutant accepted non-digest value"
  else
    fail_case "artifact hygiene field scoped hex mutation did not accept the unsafe value" "$output"
  fi

  if [ ! -x "$IAM_SIM_REPORT_RENDERER" ]; then
    fail_case "IAM simulation report renderer exists" \
      "$IAM_SIM_REPORT_RENDERER is missing or not executable"
  else
    if output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$clean_role" "$clean_out" \
        2>&1
    )" &&
       [ "$(find "$clean_out" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 2 ] &&
       validate_rendered_iam_reports \
         "$clean_out/$report_name" "$clean_out/$provenance_name" >/dev/null &&
       [ "$(grep -c '^PASS:' <<<"$output")" -eq 5 ]; then
      pass_case "report renderer clean custom/role pair passes both hygiene checks"
    else
      fail_case "report renderer clean custom/role pair" "$output"
    fi

    if output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$CUSTOM_EVIDENCE_REPORT" \
        "$ROLE_EVIDENCE_REPORT" "$evidence_out" 2>&1
    )" && validate_renderer_summary_counts \
      "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
      "$evidence_out/$report_name"; then
      pass_case "report renderer counts match committed JSON summaries"
    else
      fail_case "report renderer committed JSON summary counts" "$output"
    fi


    for role_outcome in decision deleted-pair duplicate-pair malformed-details substituted-resource; do
      role_outcome_report="$phase2_dir/renderer-role-$role_outcome.json"
      role_outcome_out="$phase2_dir/renderer-role-$role_outcome-out"
      role_outcome_case="$(dispatch_registered_mutation \
        "renderer-role-outcome-$role_outcome" \
        "$ROLE_EVIDENCE_REPORT" "$role_outcome_report" \
        "$CUSTOM_EVIDENCE_REPORT")"
      structural_diagnostic=""
      case "$role_outcome" in
        duplicate-pair)
          structural_diagnostic="role record $role_outcome_case scp_excluded details repeats action/resource pair:"
          ;;
        malformed-details)
          structural_diagnostic="role record $role_outcome_case scp_excluded details[0] must be an object"
          ;;
      esac
      if [ -n "$structural_diagnostic" ]; then
        expect_failure "renderer role outcome ${role_outcome//-/ }" \
          "$structural_diagnostic" \
          run_report_renderer "$IAM_SIM_REPORT_RENDERER" \
            "$CUSTOM_EVIDENCE_REPORT" "$role_outcome_report" "$role_outcome_out"
      elif output="$(run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$CUSTOM_EVIDENCE_REPORT" \
        "$role_outcome_report" "$role_outcome_out" 2>&1)" && \
           python3 "$IAM_SIM_FIXTURE_FACTORY" validate-renderer-role-outcome \
             "$role_outcome_out/$report_name" "$role_outcome_case"; then
        pass_case "renderer role outcome ${role_outcome//-/ } mutation -> FAIL: renderer role outcome mutant remained passing: $role_outcome_case"
      else
        fail_case "renderer role outcome ${role_outcome//-/ } mutation" "$output"
      fi
    done

    dispatch_registered_mutation renderer-scalar-resource-decision-rejection \
      "$scalar_rejection_mutant"
    if output="$(run_report_renderer \
      "$scalar_rejection_mutant" "$CUSTOM_EVIDENCE_REPORT" \
      "$ROLE_EVIDENCE_REPORT" "$scalar_rejection_out" 2>&1)"; then
      expect_failure "renderer scalar resource decision rejection" \
        "rendered custom counts differ from JSON summary" \
        validate_renderer_summary_counts \
          "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
          "$scalar_rejection_out/$report_name"
    else
      fail_case "renderer scalar resource decision rejection mutation setup" "$output"
    fi
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$CUSTOM_EVIDENCE_REPORT" \
      "$ROLE_EVIDENCE_REPORT" "$scalar_restored_out" 2>&1)" && \
       validate_renderer_summary_counts \
         "$CUSTOM_EVIDENCE_REPORT" "$ROLE_EVIDENCE_REPORT" \
         "$scalar_restored_out/$report_name" >/dev/null; then
      pass_case "renderer scalar resource decision rejection mutation restored PASS"
    else
      fail_case "renderer scalar resource decision rejection mutation restoration" "$output"
    fi

    python3 - \
      "$clean_custom" "$hash_custom" "$bad_case_custom" \
      "$unmarked_role" "$clean_role" \
      "$CUSTOM_EVIDENCE_REPORT" "$doctored_pass_custom" \
      "$role_expectation_mismatch" "$mixed_custom" <<'PY'
from copy import deepcopy
import json
from pathlib import Path
import sys

(
    clean_custom,
    hash_path,
    bad_case_path,
    unmarked_path,
    clean_role,
    evidence_custom,
    doctored_pass_path,
    role_expectation_mismatch_path,
    mixed_custom_path,
) = map(Path, sys.argv[1:])
custom = json.loads(clean_custom.read_text(encoding="utf-8"))
account_shaped_hash = "123456789012" + ("a" * 52)
custom["records"][0]["document_hashes_submitted"]["policy_input_list"][0][
    "sha256"
] = account_shaped_hash
hash_path.write_text(
    json.dumps(custom, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
bad_case = deepcopy(custom)
bad_case["records"][0]["case_id"] = (
    "case:fixture.policy:123456789012:ALL:none:matching"
)
bad_case_path.write_text(
    json.dumps(bad_case, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
role = json.loads(clean_role.read_text(encoding="utf-8"))
role_expectation_mutant = deepcopy(role)
role_expectation_mutant["records"][1]["expect"] = {
    "decision": "implicitDeny",
    "matched_sid_required": [],
    "matched_sid_forbidden": [],
}
role_expectation_mismatch_path.write_text(
    json.dumps(role_expectation_mutant, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
role.pop("account_redacted")
unmarked_path.write_text(
    json.dumps(role, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
failed_case = "case:aws_iam_policy.deployer_data:SnsSubscriptionManage:ALL:none:matching"
doctored = json.loads(evidence_custom.read_text(encoding="utf-8"))
failed = next(record for record in doctored["records"] if record["case_id"] == failed_case)
if failed.get("pass") is not False:
    raise SystemExit("FAIL: renderer doctored-pass fixture requires the failed SNS record")
failed["pass"] = True
doctored_pass_path.write_text(
    json.dumps(doctored, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
mixed = {
    "redaction_applied": True,
    "records": [{
        "case_id": "case:fixture.policy:MixedRead:ALL:none:mixed",
        "decision_observed": {
            "arn:aws:s3:::fixture/good": "allowed",
            "arn:aws:s3:::fixture/bad": "explicitDeny",
        },
        "document_hashes_submitted": {
            "permissions_boundary_policy_input_list": [],
            "policy_input_list": [{"sha256": "5" * 64}],
        },
        "expect": {
            "decision": "explicitDeny",
            "resource_decisions": {
                "arn:aws:s3:::fixture/good": "allowed",
                "arn:aws:s3:::fixture/bad": "explicitDeny",
            },
            "matched_sid_required": [],
            "matched_sid_forbidden": [],
        },
        "matched_sids": [],
        "mode": "custom",
        "pass": True,
    }],
    "summary": {"failed": 0, "passed": 1, "runner_failures": 0, "total": 1},
}
mixed_custom_path.write_text(
    json.dumps(mixed, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

    set +e
    output="$(dispatch_registered_mutation renderer-role-expectation-binding \
      "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$role_expectation_mismatch" \
      "$role_expectation_out" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [ "$fail_line" = "FAIL: role record case:fixture.policy:DenyRead:ALL:none:non-matching expectation differs from custom vector expectation" ]; then
      pass_case "renderer role expectation binding mutation -> $fail_line"
    else
      fail_case "renderer role expectation binding mutation did not fail" \
        "rc=$rc output=$output"
    fi
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$clean_role" \
      "$phase2_dir/rendered-role-expectation-restored" 2>&1)" && \
       grep -Fq '| Case ID | Scope | Expected | Custom observed | SCP-excluded | Default |' \
         "$phase2_dir/rendered-role-expectation-restored/$report_name" && \
       grep -Fq '| case:fixture.policy:DenyRead:ALL:none:non-matching | principal/custom | allowed | explicitDeny | allowed | explicitDeny |' \
         "$phase2_dir/rendered-role-expectation-restored/$report_name"; then
      pass_case "renderer role expectation binding mutation restored PASS"
    else
      fail_case "renderer role expectation binding mutation restoration" "$output"
    fi

    for expectation_mutation in missing-source empty-expectation; do
      expectation_report="$phase2_dir/renderer-legacy-role-$expectation_mutation.json"
      if [ "$expectation_mutation" = missing-source ]; then
        expectation_label="renderer legacy role expectation source"
        expectation_diagnostic="role record case:fixture.policy:UnknownRead:ALL:none:matching has no custom match and no expect"
      else
        expectation_label="renderer legacy role expectation empty"
        expectation_diagnostic="role record case:fixture.policy:UnknownRead:ALL:none:matching expect must include a supported expectation field"
      fi
      dispatch_registered_mutation \
        "$(mutation_case_id_from_label "$expectation_label")" \
        "$clean_role" "$expectation_report"
      expect_failure "$expectation_label" "$expectation_diagnostic" \
        run_report_renderer "$IAM_SIM_REPORT_RENDERER" "$clean_custom" \
          "$expectation_report" "$phase2_dir/rendered-$expectation_mutation"
    done

    while IFS='|' read -r date_case date_label date_diagnostic; do
      expect_failure "$date_label" "$date_diagnostic" \
        dispatch_registered_mutation "$date_case" \
          "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$clean_role" \
          "$phase2_dir/rendered-$date_case"
    done <<'RENDERER_DATE_REFUSALS'
renderer-mixed-modern-legacy-pair|renderer mixed modern legacy pair|all supplied reports must carry recorded_at or all must be legacy
renderer-legacy-recorded-on-required|renderer legacy recorded on required|legacy reports require --recorded-on YYYY-MM-DD
renderer-malformed-recorded-on|renderer malformed recorded on|--recorded-on must be YYYY-MM-DD
RENDERER_DATE_REFUSALS

    dispatch_registered_mutation renderer-mixed-resource-decisions "$mixed_mutant"
    if output="$(run_report_renderer \
      "$mixed_mutant" "$mixed_custom" "" "$mixed_mutant_out" 2>&1)"; then
      expect_failure "renderer mixed resource decisions" \
        "matching resource_decisions rendered as a failure" \
        validate_renderer_mixed_resource_decisions \
          "$mixed_mutant_out/$report_name"
    else
      fail_case "renderer mixed resource decisions mutation setup" "$output"
    fi
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$mixed_custom" "" \
      "$mixed_restored_out" 2>&1)" && \
       validate_renderer_mixed_resource_decisions \
         "$mixed_restored_out/$report_name"; then
      pass_case "renderer mixed resource decisions mutation restored PASS"
    else
      fail_case "renderer mixed resource decisions mutation restoration" "$output"
    fi

    dispatch_registered_mutation renderer-doctored-pass-finding \
      "$doctored_pass_renderer"
    expect_failure "renderer doctored pass finding" \
      "doctored pass suppressed renderer finding: $failed_case" \
      validate_renderer_doctored_pass \
        "$doctored_pass_renderer" "$doctored_pass_custom" \
        "$doctored_pass_out" "$failed_case"
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$CUSTOM_EVIDENCE_REPORT" "" \
      "$phase2_dir/rendered-doctored-pass-restored" 2>&1)" && \
       sed -n '/^## Findings$/,/^## Divergences$/p' \
         "$phase2_dir/rendered-doctored-pass-restored/$report_name" | \
         grep -Fq "$failed_case"; then
      pass_case "renderer doctored pass finding mutation restored PASS"
    else
      fail_case "renderer doctored pass finding mutation restoration" "$output"
    fi

    mkdir -p "$publication_out"
    printf '%s\n' 'original report sentinel' >"$publication_out/$report_name"
    printf '%s\n' 'original provenance sentinel' >"$publication_out/$provenance_name"
    dispatch_registered_mutation renderer-pair-publication-rollback \
      "$publication_mutant"
    set +e
    output="$(run_report_renderer \
      "$publication_mutant" "$clean_custom" "$clean_role" \
      "$publication_out" 2>&1)"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && \
       [ "$fail_line" = "FAIL: injected publication failure between report and provenance" ] && \
       grep -Fxq 'original report sentinel' "$publication_out/$report_name" && \
       grep -Fxq 'original provenance sentinel' "$publication_out/$provenance_name"; then
      pass_case "renderer pair publication rollback mutation -> $fail_line"
    else
      fail_case "renderer pair publication rollback mutation changed the output directory" \
        "rc=$rc output=$output"
    fi
    if output="$(run_report_renderer \
      "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$clean_role" \
      "$publication_out" 2>&1)" && \
       ! grep -Fq 'original report sentinel' "$publication_out/$report_name" && \
       ! grep -Fq 'original provenance sentinel' "$publication_out/$provenance_name"; then
      pass_case "renderer pair publication rollback mutation restored PASS"
    else
      fail_case "renderer pair publication rollback mutation restoration" "$output"
    fi

    if output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$hash_custom" "$clean_role" "$hash_out" \
        2>&1
    )" &&
       grep -Fq \
         '123456789012aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
         "$hash_out/$report_name" &&
       [ "$(grep -c '^PASS:' <<<"$output")" -eq 5 ]; then
      pass_case \
        "report renderer preserves SHA-256 while exempting its account-shaped digits"
    else
      fail_case "report renderer SHA-256 exemption" "$output"
    fi

    set +e
    output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$bad_json_custom" "" \
        "$bad_json_out" 2>&1
    )"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] &&
       grep -Fq ': account-id - non-placeholder 12-digit account id 123456789012' \
         <<<"$fail_line" &&
       [ ! -e "$bad_json_out/$report_name" ] &&
       [ ! -e "$bad_json_out/$provenance_name" ]; then
      pass_case "renderer refuses JSON report containing an unrendered account id"
    else
      fail_case "renderer refuses JSON report containing an unrendered account id" \
        "rc=$rc output=$output"
    fi

    set +e
    output="$(
      dispatch_registered_mutation renderer-account-id-case-refusal \
        "$IAM_SIM_REPORT_RENDERER" "$bad_case_custom" "" \
        "$bad_case_out" 2>&1
    )"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] &&
       grep -Fq \
         ': account-id - non-placeholder 12-digit account id 123456789012' \
         <<<"$fail_line" &&
       [ ! -e "$bad_case_out/$report_name" ] &&
       [ ! -e "$bad_case_out/$provenance_name" ]; then
      pass_case \
        "renderer account id case refusal mutation -> FAIL: rendered IAM simulation report contains a non-placeholder account id"
      printf '%s\n' "$fail_line"
    else
      fail_case "renderer account id case refusal mutation did not fail closed" \
        "rc=$rc output=$output"
    fi

    set +e
    output="$(
      dispatch_registered_mutation renderer-role-redaction-marker-refusal \
        "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$unmarked_role" \
        "$unmarked_out" 2>&1
    )"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] &&
       [ "$fail_line" = "FAIL: role report must set account_redacted to true" ] &&
       [ ! -e "$unmarked_out/$report_name" ] &&
       [ ! -e "$unmarked_out/$provenance_name" ]; then
      pass_case "renderer role redaction marker refusal mutation -> $fail_line"
    else
      fail_case \
        "renderer role redaction marker refusal mutation did not fail closed" \
        "rc=$rc output=$output"
    fi

    dispatch_registered_mutation renderer-json-hygiene-call-removal \
      "$IAM_SIM_REPORT_RENDERER" "$json_hygiene_mutant"
    if output="$(
      run_report_renderer \
        "$json_hygiene_mutant" "$bad_json_custom" "" \
        "$json_hygiene_mutant_out" 2>&1
    )" &&
       [ -f "$json_hygiene_mutant_out/$report_name" ] &&
       [ -f "$json_hygiene_mutant_out/$provenance_name" ]; then
      pass_case \
        "renderer JSON hygiene call removal mutation -> FAIL: renderer accepted JSON report containing account-id"
    else
      fail_case "renderer JSON hygiene call removal mutation did not publish" "$output"
    fi
    set +e
    output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$bad_json_custom" "" \
        "$phase2_dir/rendered-json-hygiene-restored" 2>&1
    )"
    rc=$?
    set -e
    fail_line="$(grep -m1 '^FAIL:' <<<"$output" || true)"
    if [ "$rc" -ne 0 ] && grep -Fq ': account-id -' <<<"$fail_line"; then
      pass_case "renderer JSON hygiene call removal mutation restored PASS"
    else
      fail_case "renderer JSON hygiene call removal mutation restoration" \
        "rc=$rc output=$output"
    fi

    local hygiene_mutant="$phase2_dir/iam-simulate-report-no-hygiene.sh"
    local hygiene_mutant_out="$phase2_dir/rendered-hygiene-mutant"
    dispatch_registered_mutation renderer-hygiene-call-removal \
      "$IAM_SIM_REPORT_RENDERER" "$hygiene_mutant"
    if output="$(
      run_report_renderer \
        "$hygiene_mutant" "$bad_case_custom" "" \
        "$hygiene_mutant_out" 2>&1
    )" && [ -f "$hygiene_mutant_out/$report_name" ]; then
      set +e
      checker_output="$(
        "$IAM_SIM_ARTIFACT_HYGIENE" "$hygiene_mutant_out/$report_name" 2>&1
      )"
      rc=$?
      set -e
      fail_line="$(grep -m1 '^FAIL:' <<<"$checker_output" || true)"
      if [ "$rc" -ne 0 ] && grep -Fq ': account-id -' <<<"$fail_line"; then
        pass_case \
          "renderer hygiene call removal mutation -> FAIL: published renderer mutant is rejected by artifact hygiene: account-id"
        printf '%s\n' "$fail_line"
      else
        fail_case \
          "renderer hygiene call removal mutation did not expose a rejected artifact" \
          "$checker_output"
      fi
    else
      fail_case "renderer hygiene call removal mutation did not publish" "$output"
    fi
    if output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$clean_role" \
        "$phase2_dir/rendered-hygiene-restored" 2>&1
    )" && [ "$(grep -c '^PASS:' <<<"$output")" -eq 5 ]; then
      pass_case "renderer hygiene call removal restored PASS"
    else
      fail_case "renderer hygiene call removal restoration" "$output"
    fi

    local redaction_mutant="$phase2_dir/iam-simulate-report-no-role-redaction.sh"
    local redaction_mutant_out="$phase2_dir/rendered-redaction-mutant"
    dispatch_registered_mutation renderer-account-redacted-check-removal \
      "$IAM_SIM_REPORT_RENDERER" "$redaction_mutant"
    if output="$(
      run_report_renderer \
        "$redaction_mutant" "$clean_custom" "$unmarked_role" \
        "$redaction_mutant_out" 2>&1
    )" &&
       [ -f "$redaction_mutant_out/$report_name" ] &&
       [ -f "$redaction_mutant_out/$provenance_name" ]; then
      pass_case \
        "renderer account redacted check removal mutation -> FAIL: renderer accepted role report lacking account_redacted"
    else
      fail_case \
        "renderer account redacted check removal mutation did not accept the unsafe report" \
        "$output"
    fi
    set +e
    output="$(
      run_report_renderer \
        "$IAM_SIM_REPORT_RENDERER" "$clean_custom" "$unmarked_role" \
        "$phase2_dir/rendered-redaction-restored" 2>&1
    )"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ] &&
       grep -Fxq 'FAIL: role report must set account_redacted to true' \
         <<<"$output"; then
      pass_case "renderer account redacted check removal restored PASS"
    else
      fail_case "renderer account redacted check removal restoration" \
        "rc=$rc output=$output"
    fi
  fi

  if output="$(
    grep -n $'^\t@bash tests/artifact-hygiene-contracts.sh$' "$REPO_ROOT/Makefile"
  )"; then
    pass_case "Makefile test target includes artifact hygiene contracts -> $output"
  else
    fail_case "Makefile test target includes artifact hygiene contracts"
  fi

  if [ "$failures" -eq "$group_failures" ]; then
    echo "PASS: IAM simulate REPORT group"
  else
    echo "FAIL: IAM simulate REPORT group" >&2
  fi
}
