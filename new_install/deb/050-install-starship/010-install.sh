#!/usr/bin/env bash
set -euo pipefail

sudo apt install -y starship unzip

font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$font_dir"

curl -L -o /tmp/FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
unzip -o /tmp/FiraCode.zip -d "$font_dir"
rm -f /tmp/FiraCode.zip

if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$font_dir"
fi

ensure_line() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qx "$line" "$file"; then
    printf '\n%s\n' "$line" >> "$file"
  fi
}

ensure_line 'eval "$(starship init bash)"' "$HOME/.bashrc"
ensure_line 'eval "$(starship init zsh)"' "$HOME/.zshrc"
