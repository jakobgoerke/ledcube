#!/bin/bash
# Installs the there.oughta.be LED cube software on a Raspberry Pi.
# Runs on the cube itself, as root, from a copy of this repository:
#   sudo ./device/setup.sh
# Safe to re-run: sources are reset to the pinned commits and rebuilt.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../ledcube.conf
source "$REPO_DIR/ledcube.conf"

if [[ $EUID -ne 0 ]]; then
    echo "setup.sh must run as root (sudo $0)" >&2
    exit 1
fi

SRC=$LEDCUBE_PREFIX/src
BIN=$LEDCUBE_PREFIX/bin
NEEDS_REBOOT=no

log() { printf '\n==> %s\n' "$*"; }

# Shallow-fetch a single commit into a directory and reset it to that commit.
fetch_commit() {
    local url=$1 commit=$2 dir=$3
    if [[ ! -d $dir/.git ]]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$url"
    fi
    if [[ $(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null) != "$commit" ]]; then
        git -C "$dir" fetch -q --depth 1 origin "$commit"
    fi
    git -C "$dir" checkout -q -f "$commit"
    git -C "$dir" clean -q -fdx
}

log "Installing build dependencies"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    git build-essential libegl-dev libgles-dev libegl-mesa0

log "Fetching sources"
mkdir -p "$SRC" "$BIN"
fetch_commit "$RGBMATRIX_REPO" "$RGBMATRIX_COMMIT" "$SRC/rpi-rgb-led-matrix"

log "Building rpi-rgb-led-matrix"
make -C "$SRC/rpi-rgb-led-matrix/lib" -j"$(nproc)" >/dev/null

log "Building cpu-stats-gl"
g++ -O2 -std=c++11 -o "$BIN/cpu-stats-gl.new" \
    "$REPO_DIR/device/cpu-stats-gl/cpu-stats-gl.cpp" \
    -DCORES="$CUBE_CORES" -DPORT="$CUBE_PORT" -DBLANKINTERVAL="$CUBE_BLANK" \
    -I"$SRC/rpi-rgb-led-matrix/include" \
    "$SRC/rpi-rgb-led-matrix/lib/librgbmatrix.a" \
    -lEGL -lGLESv2 -lrt -lm -lpthread
mv "$BIN/cpu-stats-gl.new" "$BIN/cpu-stats-gl"

log "Installing systemd service"
cat > /etc/default/ledcube <<EOF
# Extra rpi-rgb-led-matrix flags for cpu-stats-gl (see --led-* in its README).
# Managed by ledcube device/setup.sh; edit ledcube.conf in the repo instead.
LED_FLAGS="$LED_FLAGS"
EOF
sed "s|@PREFIX@|$LEDCUBE_PREFIX|g" "$REPO_DIR/device/ledcube.service" \
    > /etc/systemd/system/ledcube.service
systemctl daemon-reload
systemctl enable ledcube.service
systemctl restart ledcube.service

log "Disabling onboard audio"
# Pi 1-4 analog audio (snd_bcm2835) shares hardware with the matrix library,
# which refuses to start while the module is loaded. Pi 5 has no such module.
echo 'blacklist snd_bcm2835' > /etc/modprobe.d/blacklist-ledcube-audio.conf
CONFIG=/boot/firmware/config.txt
if grep -q '^dtparam=audio=on' "$CONFIG"; then
    cp "$CONFIG" "$CONFIG.bak-ledcube"
    sed -i 's/^dtparam=audio=on/dtparam=audio=off/' "$CONFIG"
    NEEDS_REBOOT=yes
fi
if grep -qw snd_bcm2835 /proc/modules; then
    NEEDS_REBOOT=yes
fi

log "Keeping the journal across reboots"
# Raspberry Pi OS keeps logs in RAM only, which hides why the cube crashed
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/50-persistent.conf
systemctl restart systemd-journald

if [[ $ISOLATE_CPU == yes ]]; then
    log "Reserving CPU 3 for the panel refresh thread"
    CMDLINE=/boot/firmware/cmdline.txt
    if ! grep -qw 'isolcpus=3' "$CMDLINE"; then
        cp "$CMDLINE" "$CMDLINE.bak-ledcube"
        sed -i '1 s/$/ isolcpus=3/' "$CMDLINE"
        NEEDS_REBOOT=yes
    fi
    if ! grep -qw 'isolcpus=3' /proc/cmdline; then
        NEEDS_REBOOT=yes
    fi
fi

log "Done"
systemctl --no-pager --lines=5 status ledcube.service || true
if [[ $NEEDS_REBOOT == yes ]]; then
    echo
    echo "A reboot is needed to activate isolcpus=3 (sudo reboot)."
fi
