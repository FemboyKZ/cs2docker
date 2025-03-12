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

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    build_ver="$(fetch_latest_cs2_version)" || continue
    build_dir="/watchdog/builds/$build_ver"
    [ -d "$build_dir" ] || continue

    rm -rf "$server_dir"/*
    flock -ns "$build_dir/.lockfile" --command "HOME=\"/tmp/cs2home\" build_ver=\"$build_ver\" build_dir=\"$build_dir\" server_dir=\"$server_dir\" /user/run.sh"
done
