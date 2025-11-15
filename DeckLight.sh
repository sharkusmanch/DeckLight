#!/bin/bash

moonlight_command='/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=moonlight com.moonlight_stream.Moonlight';
moonlight_config_file="/$HOME/.var/app/com.moonlight_stream.Moonlight/config/Moonlight Game Streaming Project/Moonlight.conf"

xrandr_info=$(xrandr -q);

current_resolution=$(echo $xrandr_info | grep -E -o 'primary [[:digit:]]+x[[:digit:]]+' | grep -E -o '[[:digit:]]+');
if [[ -z "$current_resolution" ]]; then
    current_resolution=$(echo $xrandr_info | grep -E -o 'current [[:digit:]]+ x [[:digit:]]+' | grep -E -o '[[:digit:]]+');
fi
current_refresh_rate=$(echo $xrandr_info | grep -E -o '[[:digit:]]+\.[[:digit:]]+\*' | grep -E -o '^[[:digit:]]+');
current_resolution_width=$(echo $current_resolution | grep -E -o '^[[:digit:]]+');
current_resolution_height=$(echo $current_resolution | grep -E -o '[[:digit:]]+$');


# Calculate bitrate dynamically (factor=0.10 for H.264)
factor=0.10
bitrate=$(echo "$current_resolution_width * $current_resolution_height * $current_refresh_rate * $factor / 1000" | bc)
bitrate=${bitrate%.*} # Remove decimal if present

# Update Moonlight config file
sed -i "s/fps=[[:digit:]]*/fps=$current_refresh_rate/" "$moonlight_config_file"
sed -i "s/height=[[:digit:]]*/height=$current_resolution_height/" "$moonlight_config_file"
sed -i "s/width=[[:digit:]]*/width=$current_resolution_width/" "$moonlight_config_file"
sed -i "s/bitrate=[[:digit:]]*/bitrate=$bitrate/" "$moonlight_config_file"

if [[ $1 = 'stream' && ! -z "$2" && ! -z "$3"  ]]; then
    moonlight_command="$moonlight_command $1 $2 \"$3\" $4 $5";
fi

eval $moonlight_command;
