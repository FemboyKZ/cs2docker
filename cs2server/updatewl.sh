#!/bin/bash

set -ueEo pipefail

fetch_wl_members() {
    local url="https://steamcommunity.com/groups/femwl/memberslistxml/?xml=1"
    curl -sf "$url" | xmllint --xpath "//steamID64/text()" - 2>/dev/null | grep -oE '[0-9]{17}' || echo ""
}

mkdir -p /watchdog/fkz
cp "/layers/manual.txt" "/watchdog/fkz/manual.txt"

server_dir="/tmp/cs2server"

while true; do
    members="$(fetch_wl_members)" || { 
        echo "Failed to fetch whitelist members" >&2
        sleep 60
        continue
    }

    if [ -n "$members" ]; then
        (echo "$members"; cat /watchdog/fkz/manual.txt) | sort -n -u > /tmp/whitelist.txt
    else
        cat /watchdog/fkz/manual.txt | sort -n -u > /tmp/whitelist.txt
    fi

    mv /tmp/whitelist.txt /watchdog/fkz/whitelist.txt

    target_file="$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins/Whitelist/whitelist.txt"

    if ! diff -u "/watchdog/fkz/whitelist.txt" "$target_file" > /dev/null 2>&1; then
        echo "Whitelist changed, updating server file..."

        mkdir -p "$(dirname "$target_file")"

        if [ -f "$target_file" ]; then
            cp "$target_file" "$target_file.backup" 2>/dev/null || true
        fi

        cp "/watchdog/fkz/whitelist.txt" "$target_file"
        echo "Whitelist updated successfully"
    fi

    sleep 60
done
