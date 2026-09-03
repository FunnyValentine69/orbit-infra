#!/usr/bin/env bash
# build-upstream.sh
#
# Builds the private upstream workload images (api, worker, clickhouse)
# from a `git archive` of a pinned, verified commit in a local clone of
# the upstream repo -- never the working tree. See ADR 0007 and
# ARCHITECTURE.md ("Image supply chain summary") for why this never runs
# in hosted CI: the archive step needs a private, pre-authenticated local
# clone of the upstream repo.
#
# Required env:
#   UPSTREAM_DIR    path to a local clone of the upstream repo
# Optional env:
#   IMAGE_PREFIX    tag prefix for built images (default: orbit)
#   ECR_REPOSITORY_PREFIX  bootstrap repository prefix
#                          (default: orbit-infra-79s5rw)
#   UPSTREAM_LOCK   path to the lock file (default: upstream.lock, repo root)
#   PUSH            if "1", tag/push and record ECR digests in UPSTREAM_LOCK
#   ECR_REGISTRY    required when PUSH=1
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_PREFIX="${IMAGE_PREFIX:-orbit}"
ECR_REPOSITORY_PREFIX="${ECR_REPOSITORY_PREFIX:-orbit-infra-79s5rw}"
UPSTREAM_LOCK="${UPSTREAM_LOCK:-${repo_root}/upstream.lock}"

if [[ -z "${UPSTREAM_DIR:-}" ]]; then
  echo "build-upstream: UPSTREAM_DIR is required" >&2
  exit 1
fi

if [[ "${PUSH:-0}" == "1" && -z "${ECR_REGISTRY:-}" ]]; then
  echo "build-upstream: ECR_REGISTRY is required when PUSH=1" >&2
  exit 1
fi

if [[ ! -f "$UPSTREAM_LOCK" ]]; then
  echo "build-upstream: lock file not found: $UPSTREAM_LOCK" >&2
  exit 1
fi

upstream_repo="$(grep '^upstream_repo:' "$UPSTREAM_LOCK" | sed 's/^upstream_repo:[[:space:]]*//')"
upstream_sha="$(grep '^upstream_sha:' "$UPSTREAM_LOCK" | sed 's/^upstream_sha:[[:space:]]*//')"

if [[ -z "$upstream_repo" || -z "$upstream_sha" ]]; then
  echo "build-upstream: could not read upstream_repo/upstream_sha from $UPSTREAM_LOCK" >&2
  exit 1
fi

# --- Step 2: origin must match upstream_repo ---
origin_url="$(git -C "$UPSTREAM_DIR" remote get-url origin)"
if [[ "$origin_url" != *"/${upstream_repo}.git" && "$origin_url" != *"/${upstream_repo}" ]]; then
  echo "build-upstream: UPSTREAM_DIR origin ($origin_url) does not match locked upstream_repo ($upstream_repo)" >&2
  exit 1
fi

# --- Step 3: HEAD must be exactly the locked sha ---
actual_sha="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [[ "$actual_sha" != "$upstream_sha" ]]; then
  echo "build-upstream: UPSTREAM_DIR HEAD ($actual_sha) does not match locked upstream_sha ($upstream_sha)" >&2
  exit 1
fi

# --- Step 4: working tree must be clean (tracked and untracked) ---
dirty_status="$(git -C "$UPSTREAM_DIR" status --porcelain --untracked-files=all)"
if [[ -n "$dirty_status" ]]; then
  echo "build-upstream: UPSTREAM_DIR working tree is not clean; build input must come only from the locked commit" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/build-upstream.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tar_file="${tmp_dir}/archive.tar"
archive_dir="${tmp_dir}/archive"
mkdir -p "$archive_dir"

# --- Step 5: archive the locked commit, hash the tar, then extract ---
git -C "$UPSTREAM_DIR" archive --format=tar "$upstream_sha" > "$tar_file"
build_input_sha256="$(shasum -a 256 "$tar_file" | awk '{print $1}')"
locked_input_sha256="$(grep '^build_input_sha256:' "$UPSTREAM_LOCK" | sed 's/^build_input_sha256:[[:space:]]*//')"
if [[ -n "$locked_input_sha256" && "$locked_input_sha256" != "<pending"* && "$locked_input_sha256" != "$build_input_sha256" ]]; then
  echo "build-upstream: build input hash $build_input_sha256 does not match upstream.lock ($locked_input_sha256); refusing to build from a different archive" >&2
  exit 1
fi
tar -xf "$tar_file" -C "$archive_dir"

short_sha="${upstream_sha:0:12}"

api_image="${IMAGE_PREFIX}-api"
worker_image="${IMAGE_PREFIX}-worker"
clickhouse_image="${IMAGE_PREFIX}-clickhouse"

api_repository="${ECR_REPOSITORY_PREFIX}/orbit-api"
worker_repository="${ECR_REPOSITORY_PREFIX}/orbit-worker"
clickhouse_repository="${ECR_REPOSITORY_PREFIX}/orbit-clickhouse"

# --- Step 6: build the three images ---
docker build --platform linux/arm64 \
  -f "${archive_dir}/Dockerfile.api" \
  -t "${api_image}:${short_sha}" \
  "$archive_dir"

docker build --platform linux/arm64 \
  -f "${archive_dir}/Dockerfile.worker" \
  -t "${worker_image}:${short_sha}" \
  "$archive_dir"

docker build --platform linux/arm64 \
  -f "${repo_root}/images/clickhouse/Dockerfile" \
  --build-context "upstream=${archive_dir}" \
  -t "${clickhouse_image}:${short_sha}" \
  "${repo_root}/images/clickhouse"

api_id="$(docker image inspect --format '{{.Id}}' "${api_image}:${short_sha}")"
worker_id="$(docker image inspect --format '{{.Id}}' "${worker_image}:${short_sha}")"
clickhouse_id="$(docker image inspect --format '{{.Id}}' "${clickhouse_image}:${short_sha}")"

api_digest=""
worker_digest=""
clickhouse_digest=""

if [[ "${PUSH:-0}" == "1" ]]; then
  docker tag "${api_image}:${short_sha}" "${ECR_REGISTRY}/${api_repository}:${short_sha}"
  docker push "${ECR_REGISTRY}/${api_repository}:${short_sha}"
  api_digest_ref="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${api_repository}:${short_sha}")"
  api_digest="${api_digest_ref##*@}"

  docker tag "${worker_image}:${short_sha}" "${ECR_REGISTRY}/${worker_repository}:${short_sha}"
  docker push "${ECR_REGISTRY}/${worker_repository}:${short_sha}"
  worker_digest_ref="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${worker_repository}:${short_sha}")"
  worker_digest="${worker_digest_ref##*@}"

  docker tag "${clickhouse_image}:${short_sha}" "${ECR_REGISTRY}/${clickhouse_repository}:${short_sha}"
  docker push "${ECR_REGISTRY}/${clickhouse_repository}:${short_sha}"
  clickhouse_digest_ref="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${clickhouse_repository}:${short_sha}")"
  clickhouse_digest="${clickhouse_digest_ref##*@}"

  for digest in "$api_digest" "$worker_digest" "$clickhouse_digest"; do
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      echo "build-upstream: push returned an invalid digest" >&2
      exit 1
    fi
  done

  lock_tmp="${tmp_dir}/upstream.lock"
  awk \
    -v api_repository="$api_repository" -v api_digest="$api_digest" \
    -v worker_repository="$worker_repository" -v worker_digest="$worker_digest" \
    -v clickhouse_repository="$clickhouse_repository" -v clickhouse_digest="$clickhouse_digest" \
    '
      $1 == api_repository ":" { section = "api" }
      $1 == worker_repository ":" { section = "worker" }
      $1 == clickhouse_repository ":" { section = "clickhouse" }
      section == "api" && $1 == "digest:" { print "    digest: " api_digest; section = ""; updated++; next }
      section == "worker" && $1 == "digest:" { print "    digest: " worker_digest; section = ""; updated++; next }
      section == "clickhouse" && $1 == "digest:" { print "    digest: " clickhouse_digest; section = ""; updated++; next }
      { print }
      END { if (updated != 3) exit 4 }
    ' "$UPSTREAM_LOCK" > "$lock_tmp" || {
      echo "build-upstream: could not record all three repository digests in $UPSTREAM_LOCK" >&2
      exit 1
    }
  mv "$lock_tmp" "$UPSTREAM_LOCK"
fi

# --- Step 7/8: JSON summary ---
cat <<JSON
{
  "upstream_sha": "${upstream_sha}",
  "build_input_sha256": "${build_input_sha256}",
  "images": {
    "${api_repository}": {
      "tag": "${short_sha}",
      "local_id": "${api_id}",
      "digest": "${api_digest}"
    },
    "${worker_repository}": {
      "tag": "${short_sha}",
      "local_id": "${worker_id}",
      "digest": "${worker_digest}"
    },
    "${clickhouse_repository}": {
      "tag": "${short_sha}",
      "local_id": "${clickhouse_id}",
      "digest": "${clickhouse_digest}"
    }
  }
}
JSON
