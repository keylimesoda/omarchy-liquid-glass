#!/usr/bin/env bash
set -euo pipefail
dest=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
running=$(hyprctl version -j | jq -r .abiHash)
if [ "$running" != "$(cat "$dest/hyprglass.abi")" ]; then
    notify-send "Liquid Glass needs rebuilding" "Click the glass bar button to rebuild for this Hyprland version."
    exit 1
fi
if ! hyprctl getoption plugin:hyprglass:light_strength 2>/dev/null | grep -q '^float:'; then
    hyprctl plugin load "$dest/hyprglass.so"
fi
hyprctl reload
