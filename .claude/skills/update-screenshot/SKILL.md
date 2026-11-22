---
name: update-screenshot
description: Retake preview.png, the README screenshot of the panel (normal view and Advanced open, side by side). Use after changing Panel.qml, or when someone asks to update, refresh or retake the screenshot or preview.
---

# Update the README screenshot

`preview.png` at the top of the repo shows the panel twice: as it normally looks, and with the
Advanced section open. `screenshot.sh` in this folder retakes it.

## Before running

- The plugin must be installed from this checkout and enabled. Run `./install.sh` first so the
  screenshot shows the current `Panel.qml`, not an older installed copy.
- `grim` and ImageMagick (`magick`) must be installed. Both come with Omarchy.
- Warn the person that one monitor will briefly switch to an empty workspace and the panel will
  open and close by itself. It takes about three seconds, and everything is put back afterwards.
  Ask them not to touch the mouse or keyboard meanwhile.

## Run it

```
.claude/skills/update-screenshot/screenshot.sh
```

It prints the new image size when done.

## Check the result

Open `preview.png` and look at it before calling it done:

- Both panels should be fully visible, borders included, with nothing from the desktop around
  them. If something extra got in (a notification, say), run the script again.
- The panel shows real device names and settings. Device names are fine to publish. If the
  Flux location field shows somewhere personal, set it back to the default first with
  `led schedule '{"location": [37.77, -122.42]}'` and retake the shot, then restore theirs.

Show them the new image. Don't commit unless they ask.
