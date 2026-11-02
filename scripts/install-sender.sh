#!/bin/bash
# Installs the CPU stats sender on this (Linux) PC as a systemd user service.
#   ./scripts/install-sender.sh [cube-host]
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../ledcube.conf
source "$REPO_DIR/ledcube.conf"

HOST=${1:-${LEDCUBE_SSH#*@}}

if ! python3 -c 'import psutil' 2>/dev/null; then
    echo "python3 psutil is missing; install it first, e.g.:" >&2
    echo "  sudo dnf install python3-psutil   # Fedora" >&2
    echo "  sudo apt install python3-psutil   # Debian/Ubuntu" >&2
    exit 1
fi

install -D -m 755 "$REPO_DIR/sender/ledcube-sender.py" ~/.local/bin/ledcube-sender
mkdir -p ~/.config/systemd/user
sed -e "s|@HOST@|$HOST|" -e "s|@PORT@|$CUBE_PORT|" \
    "$REPO_DIR/sender/ledcube-sender.service" > ~/.config/systemd/user/ledcube-sender.service
systemctl --user daemon-reload
systemctl --user enable --now ledcube-sender.service
systemctl --user --no-pager --lines=3 status ledcube-sender.service
