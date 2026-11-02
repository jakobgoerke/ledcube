#!/bin/bash
# Plays a short test sequence on the cube without running the sender:
# idle, single thread busy, all threads busy while heating up, cooling down.
#   ./scripts/send-test-data.sh [cube-host]
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../ledcube.conf
source "$REPO_DIR/ledcube.conf"

HOST=${1:-${LEDCUBE_SSH#*@}}

# send <temperature> <load of first thread> <load of other threads> <seconds>
send() {
    local packet=$1 i
    packet+=",$2"
    for ((i = 1; i < CUBE_CORES; i++)); do packet+=",$3"; done
    echo "$packet" > "/dev/udp/$HOST/$CUBE_PORT"
    sleep "$4"
}

send 40 0 0 3
send 40 100 0 3
for t in 43 47 50 53 57 60; do send $t 100 0 1; done
send 60 100 100 3
for t in 63 67 70 73 77 80; do send $t 100 100 1; done
send 80 0 0 3
for t in 75 70 65 60 55 50 45 40; do send $t 0 0 1; done
