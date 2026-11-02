# ledcube

Sebastian Staacks' [LED cube](https://there.oughta.be/an/led-cube) on a
Raspberry Pi with current Raspberry Pi OS (Debian 13 "trixie", 64-bit). It shows
a PC's CPU temperature (background colour) and per-thread load (the ring around
the corner) on three 64x64 HUB75 panels.

The cube runs on a Pi 3B+. A Pi 5 works too, but needs its own power supply
(see [Power](#power)).

## Quick start

```sh
./scripts/deploy.sh --reboot     # install on the cube (pi@ledcube) and reboot
./scripts/send-test-data.sh      # play a test sequence
./scripts/install-sender.sh      # stream this PC's CPU stats to the cube
```

Settings live in [`ledcube.conf`](ledcube.conf). Re-run `deploy.sh` to apply
changes. `CUBE_CORES` must match the number of threads the sender reports.

`deploy.sh` copies the repo to the cube and runs `device/setup.sh` there. It
builds a pinned [rpi-rgb-led-matrix](https://github.com/hzeller/rpi-rgb-led-matrix)
and the display program into `/opt/ledcube`, installs `ledcube.service`,
disables onboard audio (it blocks the matrix library on Pi 1–4), makes the
journal persistent, and reserves CPU 3 for the panel refresh (`isolcpus=3`).

## Hardware

- Adafruit RGB Matrix Bonnet, GPIO4–GPIO18 jumper soldered, "E" jumper set
- three chained 64x64 P2 panels with FM6126A chips
- 5 V / 10 A panel supply

For different hardware, add flags to `LED_FLAGS`:

| Symptom | Flag |
| --- | --- |
| Bonnet without the PWM jumper (dark panels) | `--led-gpio-mapping=adafruit-hat` |
| Flicker or garbage | `--led-slowdown-gpio=2` (or 3) |
| Too bright / too much current | `--led-brightness=60` |
| Lower CPU use (Pi 5) | `--led-rp1-pio=1` |

### Panel rotation

Each panel's part of the ring has to sit in the corner that touches the other
two panels. The `Remap` pixel mapper rotates each panel. Entries are in cable
order from the Bonnet: the image offset `x,y`, then the rotation (`n` none,
`s` 180°, `e` 90° counterclockwise, `w` 90° clockwise, seen from the front).

```
--led-cols=64 --led-chain=3 --led-pixel-mapper=Remap:192,64|128,0e|64,0s|0,0s
```

To redo it, set every entry to `n`, see where the ring sits, and add quarter
turns. Try it in `/etc/default/ledcube` on the cube
(`sudo systemctl restart ledcube`), then copy it into `ledcube.conf`.

### Power

The Bonnet powers the Pi from the panel supply through the GPIO header.

- **Pi 3B+** (about 1–1.5 A): works, but logs a short under-voltage warning
  every minute or two.
- **Pi 5** (up to 5 A): browns out. It froze or rebooted on service restarts,
  when the panels briefly light up fully. Power it from its own 27 W USB-C
  supply (the ribbon cable shares ground), or use a 5 V / 15 A shared supply.

That's why brightness is limited to 50%. `vcgencmd get_throttled` should read
`0x0`.

## Pi 0–3: kernel 6.18.59 or newer

On the Pi 0–3 (VC4 GPU driver), kernels without
[`bf0f3412d5a0`](https://github.com/raspberrypi/linux/commit/bf0f3412d5a0)
drop draw calls in bursts about every 20 s. The panels glitch and the kernel
logs `Failed to allocate binner memory: -12`. Raspberry Pi OS's kernel 6.18.50
is affected, so this cube runs the `rpi-update` build:

```sh
sudo SKIP_WARNING=1 rpi-update 16b655118530c1c7df85c5741737d3693f0a6948
sudo mkinitramfs -o /boot/firmware/initramfs8 6.18.59-v8+
sudo reboot
```

The next kernel update from apt replaces it.

## Changes to upstream

[`device/cpu-stats-gl/cpu-stats-gl.cpp`](device/cpu-stats-gl/cpu-stats-gl.cpp)
is upstream's
[`cpu-stats-gl.cpp`](https://github.com/Staacks/there.oughta.be/blob/7e42f53a6a4fed962aacec0216baebb0ddf21429/led-cube/led-cube/cpu-stats-gl.cpp)
(commit `7e42f53`), ported from the removed Broadcom GL driver to Mesa:

- surfaceless EGL display rendering into a pbuffer (no X, Wayland or HDMI),
  with a fallback when there's no MSAA
- binds GLES instead of desktop GL, adds `precision highp float;` to the shader
- reads pixels as `GL_RGBA` (with `GL_RGB`, Mesa returns nothing and the panels
  show noise)
- small fixes: includes, the shader error log, line-buffered stdout, and
  `CORES`, `PORT`, `BLANKINTERVAL` and `T1`–`T3` settable with `-D`

The shader, UDP protocol and panel defaults are unchanged.

## Sending data

UDP port 1234, one line per packet: `<temperature>,<load 0>,<load 1>,...`,
loads sorted in descending order. The panels blank after a few seconds without
data.

[`sender/ledcube-sender.py`](sender/ledcube-sender.py) needs `python3-psutil`.
It picks the temperature sensor automatically (`--sensor` overrides it) and
sends to `ledcube`. For Windows, see
[LEDCubeFeeder](https://github.com/Johnwulp/LEDCubeFeeder).
