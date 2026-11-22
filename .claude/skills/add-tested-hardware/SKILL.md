---
name: add-tested-hardware
description: Test the RGB devices on this machine with omarchy_led_controller and add the results to the README's tested hardware table. Use when someone wants to report or add their hardware, says "add my hardware", "test my devices", "does my X work", or wants to contribute to the tested hardware list.
---

# Add tested hardware

Help the person check that each of their RGB devices works with this plugin, then add what
you learn to the "Tested hardware" table at the bottom of `README.md`, so others with the
same hardware know what to expect.

You can't see the lights, so the person has to tell you what happened. Keep each question
short and about one device at a time.

## 1. Check the setup

Run `led state`. If it fails, the plugin isn't set up yet: point them to the Install section
of `README.md` and stop there.

Before changing anything, save their settings so you can put them back at the end:

```
cp ~/.config/led.json /tmp/led.json.before-hardware-test
```

## 2. Find the devices

- `led state` gives the device names exactly as the panel shows them.
- `openrgb -ld` adds each device's type and how it's connected (USB, I2C, ...).
- `lsusb` (USB devices) and `lspci -nn` (GPUs) give the `vendor:product` ID. Include it when
  you can match it to a device with confidence; leave it out otherwise.

Read that table and skip any device already listed with the same ID, unless the person wants
to report something different about it.

**Privacy:** the table is public. Never copy serial numbers, `/dev/...` paths, hostnames,
usernames or anything else that identifies the person's machine. Only the model, its ID,
its type and how it connects.

## 3. Test each new device

Turn every other device off first so it's obvious which lights are changing:
`led device "<other name>" off` for each of the others, and `led device "<name>" on` for this one.
Then run each step, pause, and ask what they saw:

1. `led set FF0000 -m static -b 100`: solid red?
2. `led set 0000FF -m static`: solid blue? (Checks colours really change, not just once.)
3. `led set 00FF00 -m breathing`: green, slowly fading in and out?
4. `led set FF0000 -m rainbow`: cycling through colours?
5. `led set FFFFFF -m static -b 30`: dimmer white?
6. `led device "<name>" off`, then `on`: does it go dark and come back?

Note anything odd: some LEDs staying dark, wrong colours, effects that don't show, a long
wait before changes appear. If something fails, try `led restart` once and repeat the step,
since some devices only pick up changes after the OpenRGB server restarts.

## 4. Put their settings back

```
cp /tmp/led.json.before-hardware-test ~/.config/led.json && led restore
```

Check with them that their lights look the way they did before.

## 5. Update the table

Add one row per device to the "Tested hardware" table in `README.md`, in the same style as
the existing rows:

- **Device**: the real product name, with the ID in brackets if you have it. If OpenRGB calls it
  something different, say so under Notes.
- **Type**: GPU, Cooler, LED strips, Mouse, Keyboard, RAM, Motherboard, ...
- **Connection**: USB, NVIDIA i2c, SMBus, ...
- **Status**: `Works` if all six steps passed. Otherwise `Partly works` or `Doesn't work`, and
  say what failed under Notes.
- **Notes**: a few words. Anything longer, such as a fix that took several steps, goes in its
  own page under `docs/` (see `docs/corsair-commander-pro.md` for the style), linked from
  the row. Keep setup details out of the README itself.

Show them the diff. Don't commit or push unless they ask. If they want to share it, suggest
opening a pull request with the change.
