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
#   UPSTREAM_LOCK   path to the lock file (default: upstream.lock, repo root)
#   PUSH            if "1", tag and push to ECR_REGISTRY after building
#   ECR_REGISTRY    required when PUSH=1
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_PREFIX="${IMAGE_PREFIX:-orbit}"
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
tar -xf "$tar_file" -C "$archive_dir"

short_sha="${upstream_sha:0:12}"

api_image="${IMAGE_PREFIX}-api"
worker_image="${IMAGE_PREFIX}-worker"
clickhouse_image="${IMAGE_PREFIX}-clickhouse"

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
  docker tag "${api_image}:${short_sha}" "${ECR_REGISTRY}/${api_image}:${short_sha}"
  docker push "${ECR_REGISTRY}/${api_image}:${short_sha}"
  api_digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${api_image}:${short_sha}")"

  docker tag "${worker_image}:${short_sha}" "${ECR_REGISTRY}/${worker_image}:${short_sha}"
  docker push "${ECR_REGISTRY}/${worker_image}:${short_sha}"
  worker_digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${worker_image}:${short_sha}")"

  docker tag "${clickhouse_image}:${short_sha}" "${ECR_REGISTRY}/${clickhouse_image}:${short_sha}"
  docker push "${ECR_REGISTRY}/${clickhouse_image}:${short_sha}"
  clickhouse_digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${ECR_REGISTRY}/${clickhouse_image}:${short_sha}")"
fi

# --- Step 7/8: JSON summary ---
cat <<JSON
{
  "upstream_sha": "${upstream_sha}",
  "build_input_sha256": "${build_input_sha256}",
  "images": {
    "${api_image}": {
      "tag": "${short_sha}",
      "local_id": "${api_id}",
      "digest": "${api_digest}"
    },
    "${worker_image}": {
      "tag": "${short_sha}",
      "local_id": "${worker_id}",
      "digest": "${worker_digest}"
    },
    "${clickhouse_image}": {
      "tag": "${short_sha}",
      "local_id": "${clickhouse_id}",
      "digest": "${clickhouse_digest}"
    }
  }
}
JSON
