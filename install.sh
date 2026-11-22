#!/bin/bash
# Set up everything `omarchy plugin add` can't: the `led` command on your PATH, the user
# services that keep the lights in sync, and the theme hook. Safe to rerun after every edit.
#
# Works from either place:
#   * the plugin's own folder, after `omarchy plugin add <this repo>`
#   * a separate dev checkout, in which case the plugin files are copied into Omarchy first
set -euo pipefail
cd "$(dirname "$0")"
for t in tests/test_*.py; do python3 "$t" >/dev/null; done  # stops here if any fail (set -e)

id=$(jq -r .id manifest.json)
dest=~/.config/omarchy/plugins/$id
mkdir -p "$dest" ~/.local/bin ~/.config/systemd/user

# Dev checkout: copy, don't symlink (the shell's file watcher doesn't follow symlinks). Its
# hot-reload keeps serving cached QML while bars hold the old component, so restart the shell
# when the UI changed. `led` runs fresh on every click and needs nothing.
qml_changed=0
if [[ $(realpath .) != $(realpath "$dest") ]]; then
  for f in manifest.json Panel.qml; do cmp -s "$f" "$dest/$f" || qml_changed=1; done
  install -m755 led "$dest/led"
  install -m644 manifest.json Panel.qml "$dest/"
fi
ln -sf "$dest/led" ~/.local/bin/led

install -m644 systemd/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now openrgb.service led-schedule.timer
systemctl --user enable led-idle.service && systemctl --user restart led-idle.service  # picks up new `led`

omarchy hook install theme-set hooks/led-theme-set >/dev/null

# Optional extra: only nag people who installed it.
aura=/usr/local/libexec/led-aura
[[ ! -e $aura ]] || cmp -s extras/asus-aura/led-aura "$aura" ||
  echo "motherboard helper is outdated: run sudo extras/asus-aura/install.sh"

grep -q "\"$id\"" ~/.config/omarchy/shell.json 2>/dev/null || omarchy plugin enable "$id"
if (( qml_changed )); then omarchy restart shell >/dev/null 2>&1; echo "UI changed: restarted shell"; fi
echo "installed $id"
