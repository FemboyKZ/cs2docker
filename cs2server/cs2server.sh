#!/bin/bash

set -ueEo pipefail

fetch_latest_cs2_version() {
    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?version=0&format=json&appid=730"
    curl -sf $api_url | jq -re ".response.required_version | select(type == \"number\")"
}

# Fix steamclient.so ... Why is this such a mess?
mkdir -p "/tmp/cs2home/.steam/sdk64"
cp "/watchdog/steamcmd/linux64/steamclient.so" "/tmp/cs2home/.steam/sdk64/"

server_dir="/tmp/cs2server"
mkdir -p "$server_dir"

read_layer_ver() {
    local file="/watchdog/layers/$1/latest.txt"
    [ -f "$file" ] && cat "$file" || echo ""
}

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    build_ver="$(fetch_latest_cs2_version)" || continue
    build_dir="/watchdog/cs2/builds/$build_ver"
    [ -d "$build_dir" ] || continue

    # Verify all plugin layers have a build ready
    layers_ok=1
    for layer_name in mm accel kz cssharp mam sql_mm ccvar cleaner listfix banfix wscleaner; do
        ver="$(read_layer_ver "$layer_name")"
        if [ -z "$ver" ] || [ ! -d "/watchdog/layers/$layer_name/builds/$ver" ]; then
            layers_ok=0
            break
        fi
    done
    [ $layers_ok -eq 1 ] || continue

    if [[ "${ACCEL,,}" == "css" ]]; then
        ver="$(read_layer_ver accelcss)"
        if [ -z "$ver" ] || [ ! -d "/watchdog/layers/accelcss/builds/$ver" ]; then
            continue
        fi
    fi

    rm -rf "$server_dir"/*
    # Hold shared lock on layers (blocks cleanup) and shared lock on cs2 build dir
    (
        flock -s 200
        flock -ns "$build_dir/.lockfile" --command "HOME=\"/tmp/cs2home\" build_ver=\"$build_ver\" build_dir=\"$build_dir\" server_dir=\"$server_dir\" /user/run.sh"
    ) 200>/watchdog/layers/.lockfile
done
