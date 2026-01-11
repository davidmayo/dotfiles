#!/usr/bin/env bash
set -euo pipefail

# Install VS Code extensions listed in new_install/resources/vscode-extensions.txt

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ext_file="$base_dir/resources/vscode-extensions.txt"

if [[ ! -f "$ext_file" ]]; then
  echo "No extensions list found at: $ext_file"
  exit 0
fi

# Prefer common VS Code CLI names
candidates=(code codium "code-oss" "code-insiders")
code_cmd=""
for c in "${candidates[@]}"; do
  if command -v "$c" >/dev/null 2>&1; then
    code_cmd="$c"
    break
  fi
done

if [[ -z "$code_cmd" ]]; then
  echo "No VS Code CLI found (tried: ${candidates[*]}). Install the 'code' CLI and try again." >&2
  exit 1
fi

failed=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # strip whitespace
  ext="${line%%#*}"
  ext="$(echo -n "$ext" | tr -d '[:space:]')"
  if [[ -z "$ext" ]]; then
    continue
  fi

  echo "Installing extension: $ext"
  if "$code_cmd" --install-extension "$ext" --force >/dev/null 2>&1; then
    echo "  ok: $ext"
  else
    echo "  failed: $ext" >&2
    failed=$((failed+1))
  fi
done < "$ext_file"

if [[ $failed -gt 0 ]]; then
  echo "Completed with $failed failed installs." >&2
  exit 1
fi

echo "All extensions installed successfully."
