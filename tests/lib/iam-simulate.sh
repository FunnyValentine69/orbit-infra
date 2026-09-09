#!/usr/bin/env bash

# Print the portion after the exact case:<document>:<sid>: prefix.
iam_simulate_case_suffix() {
  if [ "$#" -ne 3 ]; then
    echo "FAIL: iam_simulate_case_suffix requires case_id, document, and sid" >&2
    return 2
  fi

  local case_id=$1
  local document=$2
  local sid=$3
  local prefix="case:$document:$sid:"
  local suffix

  if [[ "$case_id" != "$prefix"* ]]; then
    echo "FAIL: case id exact prefix mismatch: expected $prefix" >&2
    return 1
  fi
  suffix="${case_id:${#prefix}}"
  if [ -z "$suffix" ]; then
    echo "FAIL: case id suffix is empty after exact prefix: $prefix" >&2
    return 1
  fi
  printf '%s\n' "$suffix"
}
