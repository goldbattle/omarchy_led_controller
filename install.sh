#!/bin/bash
# Copy the plugin into Omarchy and (re)install its user services. Safe to rerun after every edit.
set -euo pipefail
cd "$(dirname "$0")"
python3 test_led.py

dest=~/.config/omarchy/plugins/com.pgeneva.omarchy_led_controller
mkdir -p "$dest" ~/.local/bin ~/.config/systemd/user
# The shell's hot-reload keeps serving cached QML while the bars hold the old component,
# so restart it when the UI changed. `led` runs fresh on every click and needs nothing.
qml_changed=0
for f in manifest.json Panel.qml; do cmp -s "$f" "$dest/$f" || qml_changed=1; done
install -m755 led "$dest/led"
install -m644 manifest.json Panel.qml "$dest/"
ln -sf "$dest/led" ~/.local/bin/led

install -m644 systemd/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now openrgb.service led-schedule.timer

omarchy hook install theme-set hooks/led-theme-set >/dev/null

grep -q '"com.pgeneva.omarchy_led_controller"' ~/.config/omarchy/shell.json 2>/dev/null || omarchy plugin enable com.pgeneva.omarchy_led_controller
if (( qml_changed )); then omarchy restart shell >/dev/null 2>&1; echo "UI changed: restarted shell"; fi
echo "installed to $dest"
