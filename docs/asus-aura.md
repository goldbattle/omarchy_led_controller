# ASUS Aura motherboards (extra)

**Optional.** Only for ASUS boards whose lighting OpenRGB can't reach on Linux. Tested on the
PRIME X299-A. Other ASUS boards with a Nuvoton NCT6791D–NCT6796D Super I/O may work, but
haven't been tried.

## Why it's needed

OpenRGB only looks for the Aura lighting controller on the chipset's SMBus. On these boards it
sits on the Super I/O's own SMBus instead, and Linux has no built-in driver for that bus.
The out-of-tree `i2c-nct6775` kernel module adds one, but it has to be rebuilt for every kernel.

`extras/asus-aura/led-aura` does the same job from user space: a small Python port of that
driver plus OpenRGB's Aura protocol, so there is nothing to rebuild after kernel updates. It
only writes the controller's working registers, never its flash, so a power cycle always
brings back the BIOS lighting.

## Install

```
sudo extras/asus-aura/install.sh
```

Talking to the hardware directly needs root. The script installs the helper as
`/usr/local/libexec/led-aura`, owned by root so it can't be edited, and adds a sudo rule that
lets you run just that one helper without a password. The board then shows up in the panel
like any other device. Rerun after updating; the main `install.sh` tells you when.

## Remove

```
sudo rm /usr/local/libexec/led-aura /etc/sudoers.d/led-aura
```

The board disappears from the panel straight away.
