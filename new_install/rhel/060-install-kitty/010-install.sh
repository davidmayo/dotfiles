#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y kitty

if command -v update-alternatives >/dev/null 2>&1; then
  sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
  sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty
elif command -v alternatives >/dev/null 2>&1; then
  sudo alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
  sudo alternatives --set x-terminal-emulator /usr/bin/kitty
fi

if command -v gsettings >/dev/null 2>&1; then
  if gsettings list-schemas | grep -qx 'org.gnome.desktop.default-applications.terminal'; then
    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
  fi
fi
