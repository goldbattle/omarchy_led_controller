# Development

- **Install your changes:** work in a clone anywhere and run `./install.sh`. It runs the tests,
  copies the plugin into Omarchy, sets up the services and restarts the shell if the panel
  changed. Rerun it after every edit.
- **How it fits together:** `led` owns all the settings (`~/.config/led.json`) and talks to the
  OpenRGB server. `Panel.qml` only draws what `led` reports and runs `led` when you click.
  The top of `Panel.qml` explains this in more detail.
- **Tests:** `tests/` has the Python tests. They use fakes instead of real hardware, so they run
  anywhere: `for t in tests/test_*.py; do python3 "$t"; done`.

## Agent skills

The repo ships [agent skills](../.claude/skills/) for the routine checks:

- **`/run-tests`**: the Python tests, strict type checks (`mypy --strict`), shell script syntax
  and the plugin manifest. Run it before every commit.
- **`/hardware-playbook`**: a live run on your real hardware. It finds every attached device,
  then steps through effects, colours, brightness, each device switch, all off/on and the night
  schedule. After every step it reads back from OpenRGB that each device really took the change.
  Your settings are put back at the end. Run it after changing anything in `led` that talks to
  hardware.
- **`/update-screenshot`**: retakes `preview.png` for the README. Run it after changing the panel.
- **`/add-tested-hardware`**: tests each of your devices with you watching, then adds them to
  the tested hardware table in the README.

## Things worth knowing

- The `openrgb` command exits with 0 even when it fails, so `led` checks its output for errors.
- When several devices change at once, OpenRGB sometimes drops a mode change (seen on the
  Corsair Commander PRO). `led` reads the modes back after every change and re-sends any that
  didn't take; see `stuck()` in `led`.
- The plugin is copied into Omarchy, not symlinked: the shell's file watcher doesn't follow
  symlinks.
