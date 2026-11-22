# LEDs (Omarchy bar widget)

Bar widget + `led` CLI over the OpenRGB SDK server. Left-click the bulb opens the panel,
right-click toggles off. All state lives in `~/.config/led.json`; every action (panel,
right-click, terminal, night timer) goes through `led`, which makes the hardware match it.

```
./install.sh                               # test, copy into Omarchy, install services + hook, reload UI if it changed
led state
led set 8000FF -m breathing -b 60          # modes: static breathing rainbow daylight
led set theme                              # follow the Omarchy theme colour
led on | led off
led device "Corsair Commander Pro" off     # per-device switch
led night "Corsair H150i PRO RGB" off      # exclude a device from auto-off
led schedule '{"auto_off": true, "off": "22:00", "on": "09:00"}'
led restart                                # restart OpenRGB (re-detect + re-apply)
```

- **Auto-off** acts only when the window starts/ends, so turning lights on mid-window sticks
  until morning. It stacks on any mode: auto-off devices go dark, the rest keep going.
- **Theme** colour is `accent` from `~/.local/state/omarchy/current/theme/colors.toml`, the colour
  the desktop shows. Not `keyboard.rgb`: some themes override it (tokyo-night: magenta vs blue accent).
  A `theme-set` hook re-applies ~3s after a switch (it runs after Omarchy's own retint steps).
- **Gamma**: colours are converted from screen (sRGB) to linear LED drive (`"gamma"` in
  `~/.config/led.json`, or Advanced → Colour depth), otherwise pastels like theme accents show up near-white.
  Default 2.8 (a bit deeper than textbook 2.2); `1.0` disables it.
- **Advanced** (bottom of the panel): custom hex and the auto-off times.
- **Daylight** fades between clock keyframes (default: red until 06:00 → blue 08:00–17:00 →
  orange 19:00 → red 21:00). Fixed times, not real sunset; tune them with
  `led schedule '{"daylight": [["07:30","FF0000"], ["09:00","0040FF"], ...]}'`.

## Files
| File | Installed to |
|---|---|
| `manifest.json`, `Panel.qml`, `led` | `~/.config/omarchy/plugins/com.pgeneva.omarchy_led_controller/` (`led` also linked into `~/.local/bin`) |
| `systemd/openrgb.service` | user unit: OpenRGB server, runs `led restore` at login |
| `systemd/led-schedule.{service,timer}` | user units: `led tick` every minute (auto-off, daylight fade, theme drift) |
| `hooks/led-theme-set` | `~/.config/omarchy/hooks/theme-set.d/` |

The plugin is *copied*, not symlinked: the shell's inotify watcher doesn't follow symlinks. Its
hot-reload also keeps serving cached QML while bars hold the old component, so `install.sh`
restarts the shell when `Panel.qml`/`manifest.json` changed (`led`-only changes need nothing).

## Hardware (this machine)
| Device | Bus | Status |
|---|---|---|
| EVGA RTX 3080 FTW3 Ultra LHR (3842:4897) | NVIDIA i2c, addr 0x2D | works |
| Corsair Commander PRO (1b1c:0c10) | USB HID | works; both headers sized to 204 LEDs (it can't sense what's attached) |
| Corsair H150i Platinum (1b1c:0c12) | USB HID | works (OpenRGB calls it "H150i PRO RGB") |
| Logitech G502 Proteus Spectrum | USB HID | works |
| ASUS PRIME X299-A Aura | SMBus i801 (i2c-5) | **not detected**: nothing at 0x40/0x4E; 0x4F answers but isn't ENE. Check BIOS onboard-LED setting / Aura firmware before any manual probing (SMBus probing can brick RAM SPD). |

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
