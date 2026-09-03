#!/usr/bin/env bash
# Repository-wide AWS CLI boundary for lease and cleanup operations.
set -euo pipefail

TARGET="${TARGET:-}"
AWS_CLI_BIN="${AWS_CLI_BIN:-aws}"
AWS_OUTER_TIMEOUT_SECONDS="${AWS_OUTER_TIMEOUT_SECONDS:-30}"

case "$TARGET" in
  localstack)
    if [[ ! "${AWS_ENDPOINT_URL:-}" =~ ^https?://localhost(:[0-9]+)?/?$ ]]; then
      echo "aws-cli.sh: TARGET=localstack requires a localhost AWS_ENDPOINT_URL" >&2
      exit 2
    fi
    if [ "${AWS_ACCESS_KEY_ID:-}" != test ] || [ "${AWS_SECRET_ACCESS_KEY:-}" != test ]; then
      echo "aws-cli.sh: TARGET=localstack requires the repository test credentials" >&2
      exit 2
    fi
    : "${AWS_DEFAULT_REGION:?TARGET=localstack requires AWS_DEFAULT_REGION}"
    if [ "${AWS_EC2_METADATA_DISABLED:-}" != "true" ]; then
      echo "aws-cli.sh: TARGET=localstack requires AWS_EC2_METADATA_DISABLED=true" >&2
      exit 2
    fi
    unset AWS_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
    ;;
  aws)
    if [[ "${AWS_ENDPOINT_URL:-}" =~ ^https?://localhost(:[0-9]+)?/?$ ]]; then
      echo "aws-cli.sh: TARGET=aws rejects a LocalStack endpoint" >&2
      exit 2
    fi
    ;;
  *)
    echo "aws-cli.sh: TARGET is required and must be aws or localstack" >&2
    exit 2
    ;;
esac

if ! [[ "$AWS_OUTER_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "aws-cli.sh: AWS_OUTER_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

run_with_outer_timeout() {
  perl -e '
  use strict;
  use warnings;
  use POSIX qw(setpgid);

  my $seconds = shift @ARGV;
  my $pid = fork();
  die "fork failed: $!\n" unless defined $pid;
  if ($pid == 0) {
    setpgid(0, 0) or die "setpgid failed: $!\n";
    exec @ARGV;
    die "exec failed: $!\n";
  }

  $SIG{ALRM} = sub {
    kill "TERM", -$pid;
    select undef, undef, undef, 0.25;
    kill "KILL", -$pid;
    waitpid($pid, 0);
    exit 124;
  };
  alarm $seconds;
  waitpid($pid, 0);
  alarm 0;
  if ($? & 127) {
    exit 128 + ($? & 127);
  }
  exit $? >> 8;
' "$AWS_OUTER_TIMEOUT_SECONDS" "$@"
}

set +e
if [ "$TARGET" = localstack ]; then
  run_with_outer_timeout "$AWS_CLI_BIN" "$@" \
    --endpoint-url "$AWS_ENDPOINT_URL" \
    --cli-connect-timeout 5 \
    --cli-read-timeout 20
else
  run_with_outer_timeout "$AWS_CLI_BIN" "$@" \
    --cli-connect-timeout 5 \
    --cli-read-timeout 20
fi
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
  echo "aws-cli.sh: AWS command timed out after ${AWS_OUTER_TIMEOUT_SECONDS}s" >&2
fi
exit "$rc"
