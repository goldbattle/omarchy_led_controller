# Corsair Commander PRO

The Commander PRO can't tell how many LEDs are attached to its two RGB headers, so you have to
set each header's length yourself.

- **Too short:** the LEDs past that length stay dark.
- **Far too long:** at 204, Static colours still worked, but every built-in effect (Breathe,
  Rainbow) went dark.

Use the real number of LEDs on each header, or a little more. For example, 32 works for strips
of 10 LEDs:

```
openrgb -d "Corsair Commander Pro" -z 0 -sz 32 -z 1 -sz 32 && led restart
```

Don't skip the `led restart`. Until the OpenRGB server restarts, it ignores later mode changes
on this device.
