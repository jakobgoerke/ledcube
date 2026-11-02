#!/usr/bin/env python3
"""Send this PC's CPU temperature and per-thread load to the LED cube.

Packet format (UDP, one line): "<temp>,<load0>,<load1>,..." with the loads
sorted in descending order, as expected by cpu-stats-gl.
"""
import argparse
import socket
import time

import psutil

PREFERRED_SENSORS = ("k10temp", "coretemp", "zenpower", "cpu_thermal", "acpitz")


def pick_sensor(name):
    sensors = psutil.sensors_temperatures()
    if name:
        if name not in sensors:
            raise SystemExit(f"sensor {name!r} not found, available: {', '.join(sensors)}")
        return name
    for candidate in PREFERRED_SENSORS:
        if candidate in sensors:
            return candidate
    if not sensors:
        raise SystemExit("no temperature sensors found")
    return next(iter(sensors))


def read_temperature(sensor):
    return psutil.sensors_temperatures()[sensor][0].current


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="ledcube", help="cube hostname or IP (default: ledcube)")
    parser.add_argument("--port", type=int, default=1234, help="cube UDP port (default: 1234)")
    parser.add_argument("--sensor", help="psutil temperature sensor name (default: auto)")
    args = parser.parse_args()

    sensor = pick_sensor(args.sensor)
    print(f"sending {sensor} temperature and {psutil.cpu_count()} thread loads to {args.host}:{args.port}",
          flush=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    psutil.cpu_percent(percpu=True)

    while True:
        # Average the temperature over five samples, like the original script
        temperature = 0.0
        for _ in range(5):
            time.sleep(0.5)
            temperature += read_temperature(sensor)
        temperature /= 5.0

        cores = sorted(psutil.cpu_percent(percpu=True), reverse=True)
        packet = ",".join(f"{value:.1f}" for value in [temperature, *cores])
        try:
            sock.sendto(packet.encode(), (args.host, args.port))
        except OSError as error:
            # The cube may be offline or not resolvable yet; keep trying
            print(f"send failed: {error}", flush=True)


if __name__ == "__main__":
    main()
