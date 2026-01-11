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

# Build a list of entry scripts so we can report grouped outcomes.
entry_names=()
entry_count=0

for entry in "${entries[@]}"; do
  entry_path="${target_dir}/${entry}"
  scripts=()

  # Execute top-level shell scripts directly.
  if [[ -f "$entry_path" && "$entry" == *.sh ]]; then
    scripts=("$entry_path")
  elif [[ -d "$entry_path" ]]; then
    # Execute all *.sh scripts within a directory, in lexical order.
    shopt -s nullglob
    nested_scripts=("$entry_path"/*.sh)
    shopt -u nullglob

    if [[ "${#nested_scripts[@]}" -gt 0 ]]; then
      mapfile -t nested_sorted < <(printf '%s\n' "${nested_scripts[@]}" | sort)
      scripts=("${nested_sorted[@]}")
    fi
  fi

  if [[ "${#scripts[@]}" -eq 0 ]]; then
    continue
  fi

  entry_names+=("$entry")
  eval "entry_script_paths_${entry_count}=(\"\${scripts[@]}\")"
  entry_count=$((entry_count + 1))
done

# Track per-entry and per-script results for a final report.
entry_statuses=()
failed_count=0
skip_remaining=false

for entry_index in "${!entry_names[@]}"; do
  eval "scripts=(\"\${entry_script_paths_${entry_index}[@]}\")"

  if [[ "$skip_remaining" == "true" ]]; then
    entry_statuses+=("skipped")
    eval "entry_script_statuses_${entry_index}=()"
    for _ in "${scripts[@]}"; do
      eval "entry_script_statuses_${entry_index}+=(\"skipped\")"
    done
    continue
  fi

  entry_failed=false
  eval "entry_script_statuses_${entry_index}=()"

  for script in "${scripts[@]}"; do
    if [[ "$skip_remaining" == "true" ]]; then
      eval "entry_script_statuses_${entry_index}+=(\"skipped\")"
      continue
    fi

    echo "Running ${script}"
    if bash "$script"; then
      eval "entry_script_statuses_${entry_index}+=(\"ok\")"
    else
      eval "entry_script_statuses_${entry_index}+=(\"failed\")"
      failed_count=$((failed_count + 1))
      entry_failed=true
      if [[ "$continue_on_failure" == "false" ]]; then
        skip_remaining=true
      fi
    fi
  done

  if [[ "$entry_failed" == "true" ]]; then
    entry_statuses+=("failed")
    continue
  fi

  eval "script_statuses=(\"\${entry_script_statuses_${entry_index}[@]}\")"
  all_skipped=true
  for status in "${script_statuses[@]}"; do
    if [[ "$status" != "skipped" ]]; then
      all_skipped=false
      break
    fi
  done

  if [[ "$all_skipped" == "true" ]]; then
    entry_statuses+=("skipped")
  else
    entry_statuses+=("ok")
  fi
done

status_emoji() {
  case "$1" in
    ok) echo "✅" ;;
    failed) echo "❌" ;;
    skipped) echo "🟡" ;;
  esac
}

status_label() {
  case "$1" in
    ok) echo "SUCCESS" ;;
    failed) echo "FAILED" ;;
    skipped) echo "SKIPPED" ;;
  esac
}

# Print a clear report for every script, whether it ran or was skipped.
echo "Run report:"
for entry_index in "${!entry_names[@]}"; do
  entry_status="${entry_statuses[$entry_index]}"
  printf '%s %s: %s\n' "$(status_emoji "$entry_status")" "${entry_names[$entry_index]}" "$(status_label "$entry_status")"
  eval "script_statuses=(\"\${entry_script_statuses_${entry_index}[@]}\")"
  eval "script_paths=(\"\${entry_script_paths_${entry_index}[@]}\")"
  for script_index in "${!script_paths[@]}"; do
    script_name="$(basename "${script_paths[$script_index]}")"
    script_status="${script_statuses[$script_index]}"
    printf '  %s %s: %s\n' "$(status_emoji "$script_status")" "$script_name" "$(status_label "$script_status")"
  done
done

if [[ "$failed_count" -gt 0 ]]; then
  exit 1
fi
