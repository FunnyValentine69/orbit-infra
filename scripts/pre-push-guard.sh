#!/usr/bin/env bash
set -euo pipefail

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks missing; install via brew (tools.lock)"
  exit 1
fi

if ! gitleaks git --no-banner --redact .; then
  exit 1
fi

zero_sha="0000000000000000000000000000000000000000"
forbidden_path_re='(init-clickhouse\.sql|^upstream/|\.upstream-context/|terraform\.tfstate|\.tfvars$|^CLAUDE\.md$|\.env$)'
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# The pre-push hook feeds "<local ref> <local sha> <remote ref> <remote sha>"
# lines on stdin, one per pushed ref. Resolve the range per ref (for
# reporting which commits are outgoing) and collect each ref's tip sha
# separately (for the content checks below).
stdin_lines=0
commits_raw=""
tip_shas=""
while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  [ -z "${local_ref:-}" ] && continue
  stdin_lines=$((stdin_lines + 1))

  if [ -z "${local_sha:-}" ] || [ "$local_sha" = "$zero_sha" ]; then
    # Deleting a ref locally; nothing new to scan for this line.
    continue
  fi

  tip_shas="$tip_shas $local_sha"

  if [ -z "${remote_sha:-}" ] || [ "$remote_sha" = "$zero_sha" ]; then
    range="$local_sha"
  else
    range="$remote_sha..$local_sha"
  fi

  if rev_list_out="$(git rev-list "$range" 2>/dev/null)"; then
    commits_raw="$commits_raw
$rev_list_out"
  else
    commits_raw="$commits_raw
(range unavailable; scanning tip only)"
  fi
done

if [ "$stdin_lines" -eq 0 ]; then
  echo "pre-push guard: no stdin refs (manual run); scanning HEAD only"
  commits_raw="$(git rev-parse HEAD)"
  tip_shas="$(git rev-parse HEAD)"
fi

commits="$(printf '%s\n' "$commits_raw" | sed '/^$/d' | sort -u)"
tip_shas="$(printf '%s\n' "$tip_shas" | tr ' ' '\n' | sed '/^$/d' | sort -u)"

if [ -z "$commits" ]; then
  echo "pre-push guard: no commits to scan"
  echo "pre-push guard: OK"
  exit 0
fi

echo "pre-push guard: outgoing commits (reporting only):"
printf '%s\n' "$commits"

# Content checks (email-shape, forbidden paths) run against each pushed
# ref's tip commit tree/content only, not every commit in the range.
# History is gitleaks' domain (already scanned above via `gitleaks git`,
# which covers the whole range) — a commit that was already cleaned up
# further along the branch must not re-block the push just because an
# ancestor once contained it.
path_offenders=""
email_offenders=""

for tip in $tip_shas; do
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if printf '%s' "$path" | grep -q -E "$forbidden_path_re"; then
      path_offenders="$path_offenders$tip: $path
"
    fi
  done < <(git ls-tree -r --name-only "$tip")

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    content="${line#*:*:*:}"
    matches="$(printf '%s' "$content" | grep -o -i -E "$email_re" | grep -v -i -E '^(none@localhost)$' || true)"
    if [ -n "$matches" ]; then
      email_offenders="$email_offenders$line
"
    fi
  done < <(git grep -I -n -i -E "$email_re" "$tip" -- 2>/dev/null || true)
done

if [ -n "$path_offenders" ]; then
  echo "forbidden path found in outgoing tip commit(s):"
  printf '%s' "$path_offenders"
  exit 1
fi

if [ -n "$email_offenders" ]; then
  echo "email-shaped token found in outgoing tip commit(s):"
  printf '%s' "$email_offenders"
  exit 1
fi

echo "pre-push guard: OK"
