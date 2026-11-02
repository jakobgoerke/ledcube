#!/bin/bash
# Copies this repository to the cube and runs device/setup.sh there.
#   ./scripts/deploy.sh [--reboot] [user@host]
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../ledcube.conf
source "$REPO_DIR/ledcube.conf"

REBOOT=no
TARGET=$LEDCUBE_SSH
for arg in "$@"; do
    case $arg in
        --reboot) REBOOT=yes ;;
        -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
        *) TARGET=$arg ;;
    esac
done

echo "==> Copying setup files to $TARGET:ledcube-setup"
tar -C "$REPO_DIR" -cz ledcube.conf device \
    | ssh "$TARGET" 'rm -rf ledcube-setup && mkdir ledcube-setup && tar -C ledcube-setup -xz'

echo "==> Running setup on $TARGET"
ssh -t "$TARGET" 'sudo bash ledcube-setup/device/setup.sh'

if [[ $REBOOT == yes ]]; then
    echo "==> Rebooting $TARGET"
    ssh "$TARGET" 'sudo systemctl reboot' || true
fi
