#!/bin/bash
set -euo pipefail

moonlight_config_file="$HOME/.var/app/com.moonlight_stream.Moonlight/config/Moonlight Game Streaming Project/Moonlight.conf"

xrandr_info=$(xrandr -q)

# grep exits 1 when it matches nothing, which under `set -e` + pipefail would kill the script
# before the fallback below runs. Gamescope's XWayland marks no output "primary", so that is
# the normal case in Game Mode, not an edge case.
current_resolution=$(echo "$xrandr_info" | grep -E -o 'primary [[:digit:]]+x[[:digit:]]+' | grep -E -o '[[:digit:]]+x[[:digit:]]+' || true)
if [[ -z "$current_resolution" ]]; then
    current_resolution=$(echo "$xrandr_info" | grep -E -o 'current [[:digit:]]+ x [[:digit:]]+' | grep -E -o '[[:digit:]]+ x [[:digit:]]+' | tr -d ' ' || true)
fi
current_resolution_width=${current_resolution%x*}
current_resolution_height=${current_resolution#*x}

# Active refresh rate is the one marked with * in xrandr output (e.g. "60.00*" or "120*")
current_refresh_rate_raw=$(echo "$xrandr_info" | grep -E -o '[[:digit:]]+(\.[[:digit:]]+)?\*' | head -n1 | tr -d '*' || true)
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

# Bits per pixel per frame, scaled by 100 to keep the math integer (bc is not on SteamOS).
# 10 (=0.10) is conservative for H.264; 7 for HEVC, 5 for AV1.
factor_x100=10

# Optional quality knob: DECKLIGHT_QUALITY is a whole-number percentage applied to the
# computed bitrate (100 = default, 150 = +50% for better quality, 200 = double). Higher
# values trade bandwidth/latency for image quality. Defaults to 100 when unset.
quality_percent=${DECKLIGHT_QUALITY:-100}
if ! [[ "$quality_percent" =~ ^[0-9]+$ ]] || (( quality_percent <= 0 )); then
    echo "DeckLight: DECKLIGHT_QUALITY must be a positive whole number (percent), got '$quality_percent'" >&2
    exit 1
fi

# kbps = w * h * fps * (factor_x100/100) * (quality_percent/100) / 1000
bitrate=$(( current_resolution_width * current_resolution_height * current_refresh_rate * factor_x100 * quality_percent / 10000000 ))

if (( bitrate <= 0 )); then
    echo "DeckLight: failed to compute bitrate" >&2
    exit 1
fi

if [[ ! -f "$moonlight_config_file" ]]; then
    echo "DeckLight: Moonlight config not found at $moonlight_config_file" >&2
    echo "DeckLight: launch Moonlight once before using this script" >&2
    exit 1
fi

# Moonlight only writes these keys once it has saved settings at least one time, so an
# in-place substitution alone silently does nothing on a fresh config. Insert under [General].
set_key() {
    local key=$1 value=$2
    if grep -qE "^$key=" "$moonlight_config_file"; then
        sed -i "s/^$key=.*/$key=$value/" "$moonlight_config_file"
    else
        sed -i "0,/^\[General\]/s//[General]\n$key=$value/" "$moonlight_config_file"
    fi
}

set_key fps "$current_refresh_rate"
set_key height "$current_resolution_height"
set_key width "$current_resolution_width"
set_key bitrate "$bitrate"

# Moonlight 6.1.0 trips an assertion in the gamescope WSI Vulkan layer and dies on startup
# in Game Mode; bypassing the layer keeps it alive.
cmd=(/usr/bin/flatpak run --branch=stable --arch=x86_64 --env=ENABLE_GAMESCOPE_WSI=0 --command=moonlight com.moonlight_stream.Moonlight)
if [[ "${1-}" == "stream" && -n "${2-}" && -n "${3-}" ]]; then
    cmd+=(stream "$2" "$3")
    [[ -n "${4-}" ]] && cmd+=("$4")
    [[ -n "${5-}" ]] && cmd+=("$5")
fi

exec "${cmd[@]}"
