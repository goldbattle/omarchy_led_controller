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
- OpenRGB 1.1 is touchy about how changes arrive, so `led`:
  - sends every device in **one** `openrgb` run per change (`apply()`); one run per device made
    the Commander PRO drop mode changes and gave the client more chances to crash or hang;
  - learns how many colours a mode insists on once per machine (`~/.cache/led-colors.json`), so
    those batches don't trip the client's "wrong number of colours" exit;
  - leaves at least `MIN_GAP` (0.5s) between changes and takes a lock, so the panel, the timer
    and `led watch` never overlap;
  - replaces an `openrgb` run that hangs for 5s with a fresh one (the client hangs now and then
    while the server is fine);
  - reads the modes back after each change and re-sends any that didn't take (`stuck()`).
- The plugin is copied into Omarchy, not symlinked: the shell's file watcher doesn't follow
  symlinks.
