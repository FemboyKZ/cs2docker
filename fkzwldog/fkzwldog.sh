#!/bin/bash

set -ueEo pipefail

fetch_wl_members() {
    local url = "https://steamcommunity.com/groups/femwl/memberslistxml/?xml=1"
    curl -sf "$url" | xmllint --xpath "//steamID64/text()" - 2>/dev/null | grep -oE '[0-9]{17}' || echo ""
}

mkdir -p /watchdog/fkz

while true; do
    members="$(fetch_wl_members)" || { echo "Failed to fetch whitelist members" >&2; sleep 60; continue; }

    if [ -n "$members" ]; then
        (echo "$members"; cat /app/manual.txt) | sort -n -u > /tmp/whitelist.txt
    else
        cat /app/manual.txt | sort -n -u > /tmp/whitelist.txt
    fi
    mv /tmp/whitelist.txt /watchdog/fkz/whitelist.txt
    sleep 60
done
