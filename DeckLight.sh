#!/bin/bash
set -euo pipefail

moonlight_config_file="$HOME/.var/app/com.moonlight_stream.Moonlight/config/Moonlight Game Streaming Project/Moonlight.conf"

xrandr_info=$(xrandr -q)

current_resolution=$(echo "$xrandr_info" | grep -E -o 'primary [[:digit:]]+x[[:digit:]]+' | grep -E -o '[[:digit:]]+x[[:digit:]]+')
if [[ -z "$current_resolution" ]]; then
    current_resolution=$(echo "$xrandr_info" | grep -E -o 'current [[:digit:]]+ x [[:digit:]]+' | grep -E -o '[[:digit:]]+ x [[:digit:]]+' | tr -d ' ')
fi
current_resolution_width=${current_resolution%x*}
current_resolution_height=${current_resolution#*x}

# Active refresh rate is the one marked with * in xrandr output (e.g. "60.00*" or "120*")
current_refresh_rate_raw=$(echo "$xrandr_info" | grep -E -o '[[:digit:]]+(\.[[:digit:]]+)?\*' | head -n1 | tr -d '*')
current_refresh_rate=""
if [[ -n "$current_refresh_rate_raw" ]]; then
    current_refresh_rate=$(printf '%.0f' "$current_refresh_rate_raw")
fi

if ! [[ "${current_resolution_width:-}" =~ ^[0-9]+$ ]] \
   || ! [[ "${current_resolution_height:-}" =~ ^[0-9]+$ ]] \
   || ! [[ "${current_refresh_rate:-}" =~ ^[0-9]+$ ]]; then
    echo "DeckLight: failed to parse display info from xrandr (width='${current_resolution_width:-}' height='${current_resolution_height:-}' fps='${current_refresh_rate:-}')" >&2
    exit 1
fi

# factor = bits per pixel per frame. 0.10 is conservative for H.264; ~0.07 for HEVC, ~0.05 for AV1.
factor=0.10
bitrate=$(echo "$current_resolution_width * $current_resolution_height * $current_refresh_rate * $factor / 1000" | bc)

if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
    echo "DeckLight: failed to compute bitrate" >&2
    exit 1
fi

if [[ ! -f "$moonlight_config_file" ]]; then
    echo "DeckLight: Moonlight config not found at $moonlight_config_file" >&2
    echo "DeckLight: launch Moonlight once before using this script" >&2
    exit 1
fi

sed -i "s/fps=[[:digit:]]*/fps=$current_refresh_rate/" "$moonlight_config_file"
sed -i "s/height=[[:digit:]]*/height=$current_resolution_height/" "$moonlight_config_file"
sed -i "s/width=[[:digit:]]*/width=$current_resolution_width/" "$moonlight_config_file"
sed -i "s/bitrate=[[:digit:]]*/bitrate=$bitrate/" "$moonlight_config_file"

cmd=(/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=moonlight com.moonlight_stream.Moonlight)
if [[ "${1-}" == "stream" && -n "${2-}" && -n "${3-}" ]]; then
    cmd+=(stream "$2" "$3")
    [[ -n "${4-}" ]] && cmd+=("$4")
    [[ -n "${5-}" ]] && cmd+=("$5")
fi

exec "${cmd[@]}"
