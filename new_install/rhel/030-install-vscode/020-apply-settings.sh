#!/usr/bin/env bash
set -euo pipefail

# Applies new_install/resources/vscode-settings.json into the user's VS Code
# settings.json by deep-merging dictionaries. Incoming values overwrite existing
# keys. Leaves other keys intact. Creates a timestamped backup of the original.

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
incoming="$base_dir/resources/vscode-settings.json"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
candidate_paths=(
  "$XDG_CONFIG_HOME/Code/User/settings.json"
  "$XDG_CONFIG_HOME/Code - OSS/User/settings.json"
  "$XDG_CONFIG_HOME/Code - Insiders/User/settings.json"
)

# Pick the first existing path or default to the primary path
target="${candidate_paths[0]}"
for p in "${candidate_paths[@]}"; do
  if [[ -f "$p" ]]; then
    target="$p"
    break
  fi
done

if [[ ! -f "$incoming" ]]; then
  echo "No incoming settings file found at: $incoming"
  exit 0
fi

mkdir -p "$(dirname "$target")"

if [[ -f "$target" ]]; then
  cp "$target" "$target.bak.$(date +%s)"
  echo "Backed up existing settings to $target.bak.*"
fi

python3 - "$incoming" "$target" <<'PY'
import json,sys,os

inc_path = sys.argv[1]
target_path = sys.argv[2]

def load_json(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}

def deep_merge(a, b):
    for k, v in b.items():
        if k in a and isinstance(a[k], dict) and isinstance(v, dict):
            deep_merge(a[k], v)
        else:
            a[k] = v
    return a

incoming = load_json(inc_path)
existing = load_json(target_path) if os.path.exists(target_path) else {}
merged = deep_merge(existing, incoming)

with open(target_path, 'w', encoding='utf-8') as f:
    json.dump(merged, f, indent=2, ensure_ascii=False)

print(f"Merged settings from {inc_path} into {target_path}")
PY

echo "Apply complete."
