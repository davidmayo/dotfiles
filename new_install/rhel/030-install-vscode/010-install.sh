#!/usr/bin/env bash
set -euo pipefail

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat <<'REPO' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO

sudo dnf install -y code
