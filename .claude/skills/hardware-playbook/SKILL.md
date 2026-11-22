---
name: hardware-playbook
description: Live end-to-end check of omarchy_led_controller on the real RGB hardware attached to this machine. Steps through effects, colours, brightness, every device switch, all off/on and the night schedule, reading back after each step that every device really took the change. Use after changing led or anything that talks to hardware, when lights don't do what the panel says, or when asked to test the real hardware.
---

# Hardware playbook

`playbook.py` in this folder drives the installed `led` command through a fixed list of
changes. It works with whatever is attached: it reads the device list from `led state` first.
After each step it asks OpenRGB which mode every device is really in and compares that with
what `led` should have set. Then it puts the person's own settings back, even if a step fails.

## Before running

- Run `./install.sh` first, so the installed `led` is the code you want to test.
- Tell the person their lights will change for about a minute and then return to normal.
- Ask whether they want to watch. OpenRGB can report modes but not colours, so a person
  watching is the only way to check that colours look right. If they do, use `--watch 3` to
  pause three seconds after each step.

## Run it

```
.claude/skills/hardware-playbook/playbook.py            # automatic checks only
.claude/skills/hardware-playbook/playbook.py --watch 3  # with time to look at each step
```

Each step prints `PASS` or `FAIL`, and failures list each device that's in the wrong mode.
The script exits non-zero if anything failed. Devices driven by an extra (such as the ASUS
motherboard) can't be read back and are listed as skipped.

## If a step fails

- Run it again once. If the same step fails twice, it's real.
- Reproduce that step by hand with `led` and check with `openrgb -ld` (the active mode is the
  one in `[brackets]`).
- A device that ignores a mode change, or only takes it after a delay, points at OpenRGB rather
  than `led`. Compare against `stuck()` in `led`, which already re-sends dropped changes once.
- If `led` itself errors, the message is in the step's output.

## Report

How many steps passed, every failure with its device and expected mode, and whether the
person's settings came back (the script prints "settings restored"). If they watched, include
anything they say looked wrong.
