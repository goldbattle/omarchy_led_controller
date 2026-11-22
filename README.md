# LEDs (Omarchy bar widget)

Bar widget + `led` CLI over the OpenRGB SDK server. Left-click the bulb opens the panel,
right-click toggles off. All state lives in `~/.config/led.json`; every action (panel,
right-click, terminal, night timer) goes through `led`, which makes the hardware match it.

```
./install.sh                               # test, copy into Omarchy, install services + hook, reload UI if it changed
led state
led set 8000FF -m breathing -b 60          # modes: static breathing rainbow flux
led set theme                              # follow the Omarchy theme colour
led on | led off
led device "Corsair Commander Pro" off     # per-device switch
led schedule '{"auto_off": true, "off": "22:00", "on": "09:00"}'
led restart                                # restart OpenRGB (re-detect + re-apply)
```

- **Auto-off** darkens every device for the window; at the end only devices whose switch is on
  come back. It acts only when the window starts/ends, so turning lights on mid-window sticks
  until morning. Works with any mode.
- **Theme** colour is `accent` from `~/.local/state/omarchy/current/theme/colors.toml`, the colour
  the desktop shows. Not `keyboard.rgb`: some themes override it (tokyo-night: magenta vs blue accent).
  A `theme-set` hook re-applies ~3s after a switch (it runs after Omarchy's own retint steps).
- **Gamma**: colours are converted from screen (sRGB) to linear LED drive (`"gamma"` in
  `~/.config/led.json`, or Advanced → Colour depth), otherwise pastels like theme accents show up near-white.
  Default 2.8 (a bit deeper than textbook 2.2); `1.0` disables it.
- **Off while screens are off** (Advanced, default on): `led watch` (`led-idle.service`) polls
  `hyprctl monitors` every 2s and darkens everything once all monitors are DPMS-off, i.e. after
  the screensaver/lock blanks them; lights return within ~2s of waking.
- **Advanced** (bottom of the panel): custom hex and the auto-off times.
- **Flux** follows the sun, not the clock: white (6500K) while it's >6 deg up, 3400K at sunset,
  2700K, 1900K (candlelight) at civil dusk, then fading to pure red by nautical dusk (-12 deg);
  mornings mirror it. The chip shows the current target. Location defaults to San Francisco;
  change it in Advanced or with `led schedule '{"location": [lat, lon]}'`.

## Files
| File | Installed to |
|---|---|
| `manifest.json`, `Panel.qml`, `led` | `~/.config/omarchy/plugins/com.pgeneva.omarchy_led_controller/` (`led` also linked into `~/.local/bin`) |
| `systemd/openrgb.service` | user unit: OpenRGB server, runs `led restore` at login |
| `systemd/led-idle.service` | user unit (graphical session): `led watch` |
| `systemd/led-schedule.{service,timer}` | user units: `led tick` every minute (auto-off, flux steps, theme drift) |
| `hooks/led-theme-set` | `~/.config/omarchy/hooks/theme-set.d/` |

The plugin is *copied*, not symlinked: the shell's inotify watcher doesn't follow symlinks. Its
hot-reload also keeps serving cached QML while bars hold the old component, so `install.sh`
restarts the shell when `Panel.qml`/`manifest.json` changed (`led`-only changes need nothing).

## Hardware (this machine)
| Device | Bus | Status |
|---|---|---|
| EVGA RTX 3080 FTW3 Ultra LHR (3842:4897) | NVIDIA i2c, addr 0x2D | works |
| Corsair Commander PRO (1b1c:0c10) | USB HID | works; LED strips, both headers sized to **32** LEDs (it can't sense what's attached). At 204 Direct/Static still worked but every hardware effect (Breathe/Rainbow) rendered dark. If the last LEDs stay dark raise it (strips are 10 LEDs each): `openrgb -d "Corsair Commander Pro" -z 0 -sz N -z 1 -sz N && led restart` (without the restart the server ignores later mode changes on it) |
| Corsair H150i Platinum (1b1c:0c12) | USB HID | works (OpenRGB calls it "H150i PRO RGB") |
| Logitech G502 Proteus Spectrum | USB HID | works |
| ASUS PRIME X299-A Aura (ENE `AUMA0-E6K5-0104`, 7 LEDs) | Nuvoton NCT6796D Super I/O SMBus (base 0x2c0), addr 0x4E | works via `led-aura` (not OpenRGB: Linux has no driver for that SMBus) |

## Motherboard backend (`led-aura`)
OpenRGB only finds Aura on the chipset SMBus; on this board it sits behind the Super I/O's own
SMBus, which needs the out-of-tree `i2c-nct6775` kernel module. Instead `led-aura` is a
stdlib-Python port of that driver (via `/dev/port`) plus OpenRGB's ENE register protocol and
detection test, so nothing needs rebuilding on kernel updates. It only touches RAM registers
(never the controller's flash), so a power cycle restores BIOS lighting. Raw port I/O needs root:
```
sudo ./install-aura.sh   # once, and again when led-aura changes (install.sh reminds you)
```
installs it root-owned at `/usr/local/libexec/led-aura` with a sudo rule for just that helper.
`led` then shows the board as a fifth device (probe cached per boot in `/run/user/$UID`).

## One-time system setup (not in install.sh, needs root)
```
sudo pacman -S openrgb                       # ships udev rules (uaccess for hidraw + i2c)
echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf && sudo modprobe i2c-dev
```
Then in `~/.config/OpenRGB/OpenRGB.json` set `Detectors.detectors["Logitech HID++ 2.0"] = false`:
that detector loops on the Unifying receiver and stalls detection ~90s (0.8s without it).

## OpenRGB CLI gotchas `led` works around
- Exit code is 0 even on errors, so output text is checked.
- Some modes need exactly N colours ("Color Pulse", "Pulsing" = 2): `led` reads the error and repeats the colour.
- Direct mode on Corsair needs a keepalive, which is why the server must stay running.
