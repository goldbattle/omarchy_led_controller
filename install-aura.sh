#!/bin/bash
# One-time root setup for the motherboard (ASUS Aura) backend: install the led-aura helper
# root-owned (so it can't be edited into something else) and let this user run exactly that
# helper without a password. Rerun after led-aura changes; ./install.sh tells you when.
set -euo pipefail
[[ $EUID == 0 ]] || exec sudo "$0" "$@"
user=${SUDO_USER:-$(id -un "${PKEXEC_UID:?run with sudo or pkexec}")}
cd "$(dirname "$0")"

install -D -o root -g root -m 755 led-aura /usr/local/libexec/led-aura

rule=$(mktemp)
echo "$user ALL=(root) NOPASSWD: /usr/local/libexec/led-aura" >"$rule"
visudo -cf "$rule" >/dev/null  # never install a rule that would break sudo
install -o root -g root -m 440 "$rule" /etc/sudoers.d/led-aura
rm -f "$rule"

rm -f /run/user/*/led-aura.json  # make led re-probe
echo "led-aura installed for $user"
