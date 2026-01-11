#!/usr/bin/env bash
# Fail fast on errors, unset variables, and pipeline failures.
set -euo pipefail

# By default, stop at the first failure. Use --continue to keep going.
continue_on_failure=false
for arg in "$@"; do
  case "$arg" in
    --continue)
      continue_on_failure=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

# Determine which distro family we belong to based on os-release metadata
# and simple file-based fallbacks.
get_distro_family() {
  local id="${1:-}"
  local id_like="${2:-}"

  # RHEL-like distributions.
  if [[ "$id" =~ ^(rhel|fedora|centos|rocky|almalinux)$ ]] || [[ "$id_like" =~ (rhel|fedora|centos) ]]; then
    echo "rhel"
    return 0
  fi

  # Debian-like distributions.
  if [[ "$id" =~ ^(debian|ubuntu|linuxmint|pop|raspbian)$ ]] || [[ "$id_like" =~ (debian|ubuntu) ]]; then
    echo "deb"
    return 0
  fi

  # Arch-like distributions.
  if [[ "$id" =~ ^(arch|manjaro)$ ]] || [[ "$id_like" =~ (arch) ]]; then
    echo "arch"
    return 0
  fi

  # Fall back to release marker files if /etc/os-release isn't sufficient.
  if [[ -f /etc/redhat-release ]]; then
    echo "rhel"
    return 0
  fi

  if [[ -f /etc/debian_version ]]; then
    echo "deb"
    return 0
  fi

  if [[ -f /etc/arch-release ]]; then
    echo "arch"
    return 0
  fi

  return 1
}

# Read /etc/os-release if present to gather ID and ID_LIKE.
id=""
id_like=""
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  id="${ID:-}"
  id_like="${ID_LIKE:-}"
fi

# Resolve the distro family or fail clearly.
if ! distro_family="$(get_distro_family "$id" "$id_like")"; then
  echo "Unsupported distro. Unable to determine RHEL/Debian/Arch family from /etc/os-release." >&2
  exit 1
fi

# Locate the script tree for the chosen distro.
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${base_dir}/${distro_family}"

if [[ ! -d "$target_dir" ]]; then
  echo "Expected distro directory not found: $target_dir" >&2
  exit 1
fi

# List entries in the distro directory in lexical order.
mapfile -t entries < <(ls -1 "$target_dir" 2>/dev/null | sort)

# Build a list of scripts to run in the intended order so we can report
# outcomes even if we stop early.
scripts_to_run=()

for entry in "${entries[@]}"; do
  entry_path="${target_dir}/${entry}"

  # Execute top-level shell scripts directly.
  if [[ -f "$entry_path" && "$entry" == *.sh ]]; then
    scripts_to_run+=("$entry_path")
  elif [[ -d "$entry_path" ]]; then
    # Execute all *.sh scripts within a directory, in lexical order.
    shopt -s nullglob
    nested_scripts=("$entry_path"/*.sh)
    shopt -u nullglob

    if [[ "${#nested_scripts[@]}" -gt 0 ]]; then
      mapfile -t nested_sorted < <(printf '%s\n' "${nested_scripts[@]}" | sort)
    else
      nested_sorted=()
    fi

    for script in "${nested_sorted[@]}"; do
      scripts_to_run+=("$script")
    done
  fi
done

# Track per-script results for a final report.
statuses=()
failed_count=0

for script in "${scripts_to_run[@]}"; do
  echo "Running ${script}"
  if bash "$script"; then
    statuses+=("ok")
  else
    statuses+=("failed")
    failed_count=$((failed_count + 1))
    if [[ "$continue_on_failure" == "false" ]]; then
      break
    fi
  fi
done

if [[ "${#statuses[@]}" -lt "${#scripts_to_run[@]}" ]]; then
  remaining=$(( ${#scripts_to_run[@]} - ${#statuses[@]} ))
  for ((i = 0; i < remaining; i++)); do
    statuses+=("skipped")
  done
fi

# Print a clear report for every script, whether it ran or was skipped.
echo "Run report:"
for i in "${!scripts_to_run[@]}"; do
  printf '  %s: %s\n' "${scripts_to_run[$i]}" "${statuses[$i]}"
done

if [[ "$failed_count" -gt 0 ]]; then
  exit 1
fi
