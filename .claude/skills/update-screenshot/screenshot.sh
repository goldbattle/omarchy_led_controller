#!/bin/bash
# Retake preview.png, the screenshot at the top of the README: the panel as it normally
# looks, and next to it with the Advanced section open.
#
# How: open the panel over an empty workspace, take shots with it closed, open, and open with
# Advanced expanded, and crop each open shot to the area that changed. Only the panel ends
# up in the picture, never your windows. Your workspace is restored afterwards.
#
# Needs the plugin installed and enabled (./install.sh), plus grim and ImageMagick.
# Run from anywhere; it always writes preview.png at the top of the repo.
set -euo pipefail
cd "$(dirname "$0")/../../.."  # the repo root
id=$(jq -r .id manifest.json)
tmp=$(mktemp -d)

# The monitor showing the panel, found by its layer-shell surface.
panel_monitor() {
  hyprctl layers -j | jq -r 'to_entries[]
    | select(any(.value.levels[][]; .namespace == "omarchy-keyboard-panel")) | .key'
}

omarchy-shell "$id" open && sleep 1
mon=$(panel_monitor)
omarchy-shell "$id" close
[[ -n $mon ]] || { echo "panel didn't open: is $id enabled?" >&2; exit 1; }

# Swap that monitor to an empty workspace so nothing behind the panel moves between shots.
home=$(hyprctl activeworkspace -j | jq -r .monitor)
focus() { hyprctl dispatch "hl.dsp.focus({ $1 = \"$2\" })" >/dev/null; }  # Hyprland 0.56+ Lua syntax
focus monitor "$mon"
ws=$(hyprctl activeworkspace -j | jq .id)
trap 'omarchy-shell "$id" close; focus workspace "$ws"; focus monitor "$home"; rm -rf "$tmp"' EXIT
focus workspace empty && sleep 0.5

grim -o "$mon" "$tmp/closed.png"
omarchy-shell "$id" open && sleep 1  # let the open animation finish
grim -o "$mon" "$tmp/normal.png"
omarchy-shell "$id" setAdvanced true && sleep 0.5
grim -o "$mon" "$tmp/advanced.png"
omarchy-shell "$id" setAdvanced false

# Crop a shot to the area that differs from the closed one. The morphology step drops thin
# changes such as a clock ticking in the bar and keeps only solid areas, i.e. the panel card;
# the dilate wins back the thin border the first step shaved off.
crop() {
  local box
  box=$(magick "$tmp/closed.png" "$tmp/$1.png" -compose difference -composite \
    -threshold 2% -morphology Open Square:8 -morphology Dilate Square:3 -format '%@' info:)
  magick "$tmp/$1.png" -crop "$box" +repage "$tmp/$1-crop.png"
}
crop normal
crop advanced

# Side by side, top-aligned, with a transparent gap between them.
magick "$tmp/normal-crop.png" -background none -gravity east -splice 24x0 \
  "$tmp/advanced-crop.png" -gravity north +append preview.png
echo "wrote preview.png ($(magick identify -format '%wx%h' preview.png))"
