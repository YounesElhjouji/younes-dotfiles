#!/usr/bin/env bash
set -euo pipefail

config="${K8S_CLUSTERS_CONFIG:-$HOME/.k8s-clusters}"

if ! command -v kubectl >/dev/null 2>&1; then
  exit 0
fi

context="$(kubectl config current-context 2>/dev/null || true)"
if [ -z "$context" ]; then
  exit 0
fi

if [ -f "$config" ]; then
  alias_name="$(
    awk -v context="$context" '
      /^[[:space:]]*($|#)/ { next }
      $2 == context { print $1; found=1; exit }
      END { exit found ? 0 : 1 }
    ' "$config" 2>/dev/null || true
  )"

  if [ -n "$alias_name" ]; then
    printf '%s' "$alias_name"
    exit 0
  fi
fi

printf '%s' "$context"
