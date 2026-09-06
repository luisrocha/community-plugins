#!/bin/sh
# Evaluate only; never rebuild, activate, or modify the source lockfile.
set -eu
source_path=$1
input=$2
configuration=$3
username=$4
plugin_path=$5
preview_dir=$(mktemp -d /tmp/nix-monitor-preview.XXXXXXXX)
trap 'rm -rf -- "$preview_dir"' EXIT
trap 'exit 1' HUP INT TERM
# Preserve build-output symlinks instead of traversing the entire Nix store.
cp -R --no-preserve=mode -- "$source_path/." "$preview_dir/flake"
# The lock may itself be a symlink; update only an independent regular copy.
cp -L --remove-destination --no-preserve=mode -- "$source_path/flake.lock" "$preview_dir/flake/flake.lock"
nix-instantiate --eval --strict --json "$plugin_path/package-versions.nix" \
  --argstr flakePath "$preview_dir/flake" --argstr configuration "$configuration" \
  --argstr username "$username" > "$preview_dir/current-packages.json"
nix flake update --flake "path:$preview_dir/flake" "$input" >&2
nix-instantiate --eval --strict --json "$plugin_path/package-versions.nix" \
  --argstr flakePath "$preview_dir/flake" --argstr configuration "$configuration" \
  --argstr username "$username" > "$preview_dir/newest-packages.json"
nix-instantiate --eval --strict --json "$plugin_path/compare-packages.nix" \
  --argstr currentFile "$preview_dir/current-packages.json" \
  --argstr newestFile "$preview_dir/newest-packages.json" > "$preview_dir/comparison.json"
NIX_MONITOR_COMPARISON="$preview_dir/comparison.json" nix eval --raw --impure \
  --expr 'builtins.fromJSON (builtins.readFile (builtins.getEnv "NIX_MONITOR_COMPARISON"))'
