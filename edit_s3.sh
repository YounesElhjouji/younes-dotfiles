#!/usr/bin/env bash
set -euo pipefail

# edit-s3.sh
# Download an S3 object to a temp file, open in nvim, then upload it back.
# Defaults to Nebius Object Storage endpoint; override with --endpoint.

usage() {
  cat <<EOF
Usage: $(basename "$0") s3://bucket/key [--endpoint ENDPOINT_URL]

Examples:
  $(basename "$0") s3://kosmical-poc/datasets/video-dataset/env-foo/bar.json
  $(basename "$0") s3://my-aws-bucket/path/file.txt --endpoint https://s3.amazonaws.com

Notes:
  - Requires AWS CLI configured with credentials that can access the bucket.
  - --endpoint is optional; default is Nebius: https://storage.us-central1.nebius.cloud
  - Uses nvim for editing. Set EDITOR to override (e.g., EDITOR=vim ./edit-s3.sh ...).
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

S3_URI=""
ENDPOINT="${ENDPOINT:-https://storage.us-central1.nebius.cloud}"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    s3://*)
      S3_URI="$1"
      shift
      ;;
    --endpoint)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --endpoint requires a value" >&2
        exit 1
      fi
      ENDPOINT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$S3_URI" ]]; then
  echo "ERROR: Missing S3 URI" >&2
  usage
  exit 1
fi

# Ensure aws CLI exists
if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found. Install AWS CLI first." >&2
  exit 1
fi

# Resolve editor (default to nvim, then vim, then vi)
EDITOR_BIN="${EDITOR:-}"
if [[ -z "$EDITOR_BIN" ]]; then
  if command -v nvim >/dev/null 2>&1; then
    EDITOR_BIN="nvim"
  elif command -v vim >/dev/null 2>&1; then
    EDITOR_BIN="vim"
  else
    EDITOR_BIN="vi"
  fi
fi

# Cross-platform hash function (macOS uses shasum; Linux often has sha256sum)
hash_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  else
    # Fallback: no hash available, always "changed"
    echo "nohash"
  fi
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR" || true
}
trap cleanup EXIT

FNAME="$(basename "$S3_URI")"
LOCAL_PATH="$TMP_DIR/$FNAME"

echo "[edit-s3] Downloading: $S3_URI"
aws s3 cp "$S3_URI" "$LOCAL_PATH" --endpoint-url "$ENDPOINT"

ORIG_HASH="$(hash_file "$LOCAL_PATH")"

echo "[edit-s3] Opening editor: $EDITOR_BIN $LOCAL_PATH"
"$EDITOR_BIN" "$LOCAL_PATH"

NEW_HASH="$(hash_file "$LOCAL_PATH")"

if [[ "$ORIG_HASH" != "nohash" && "$NEW_HASH" == "$ORIG_HASH" ]]; then
  echo "[edit-s3] No changes detected. Skipping upload."
  exit 0
fi

echo "[edit-s3] Uploading updated file to: $S3_URI"
aws s3 cp "$LOCAL_PATH" "$S3_URI" --endpoint-url "$ENDPOINT"

echo "[edit-s3] Done."
