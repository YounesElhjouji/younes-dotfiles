#!/usr/bin/env bash
set -euo pipefail

source_dir=${1:?source checkout required}
output_dir=${2:?output directory required}
recipe_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/codex-compact-target}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
# Avoid enormous LTO/debug artifacts on developer VMs. These affect the build,
# not the model configuration, tools, context, or inference settings.
export CARGO_PROFILE_RELEASE_LTO=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
export CARGO_PROFILE_RELEASE_DEBUG=0
export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_PROFILE_RELEASE_OPT_LEVEL=2

cd "$source_dir/codex-rs"
python3 "$recipe_dir/normalize_lock.py" .
just fmt-check
just clippy -p codex-tui --release --locked
just test -p codex-tui --release --locked
cargo build -p codex-cli --bin codex --release --locked
mkdir -p "$output_dir"
cp "$CARGO_TARGET_DIR/release/codex" "$output_dir/codex"
cp Cargo.lock "$output_dir/Cargo.lock"
