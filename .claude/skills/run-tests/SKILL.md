---
name: run-tests
description: Run every check for omarchy_led_controller - the Python tests in tests/, strict type checks of led, the extras and the tests, shell script syntax, and the plugin manifest. Use after changing code, before committing, or when someone asks to run the tests or check the project.
---

# Run the tests

Run each step from the top of the repo, even if an earlier one fails, then report all the
results together. None of these touch the lights or need root.

## 1. Python tests

```
for t in tests/test_*.py; do echo "$t"; python3 "$t"; done
```

Each file prints `ok` when everything in it passes. A failure stops that file with an
`AssertionError` pointing at the line that failed. The tests use fakes for OpenRGB, hyprctl and
the motherboard bus, so they run anywhere.

## 2. Type checks

Everything is fully typed, and checked in strict mode:

```
uvx mypy --strict --python-version 3.14 --scripts-are-modules led extras/asus-aura/led-aura tests/*.py
```

This needs `uv` (it fetches mypy on first use). If `uvx` isn't installed, ask before installing it
(`sudo pacman -S uv`). If they'd rather not, skip this step and say so in the report.

New code must keep this passing: give every function, parameter and return a type, and use the
`Config`, `Runtime` and `Device` types at the top of `led` rather than plain `dict`.

## 3. Shell scripts

```
bash -n install.sh extras/asus-aura/install.sh .claude/skills/update-screenshot/screenshot.sh hooks/led-theme-set
```

No output means the syntax is fine.

## 4. Plugin manifest

```
omarchy plugin validate .
```

The same check Omarchy runs before it will install the plugin. Skip it if `omarchy` isn't
available (not on Omarchy), and say so.

## Report

One line per step: passed, failed (with the first error), or skipped (and why). If something
failed, offer to fix it, but don't change code without asking.
