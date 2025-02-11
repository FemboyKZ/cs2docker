#!/bin/bash

set -ueEo pipefail

fetch_latest_cs2_version() {
    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?version=0&format=json&appid=730"
    curl -sf $api_url | jq -re ".response.required_version | select(type == \"number\")"
}

# Fix steamclient.so ... Why is this such a mess?
mkdir -p "/tmp/cs2home/.steam/sdk64"
cp "/repo/steamcmd/linux64/steamclient.so" "/tmp/cs2home/.steam/sdk64/"

mkdir -p "/tmp/cs2server"
cd "/tmp/cs2server"

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    latest_version="$(fetch_latest_cs2_version)" || continue
    [ -d "/repo/builds/$latest_version" ] || continue

    flock -ns "/repo/builds/$latest_version/.lockfile" --command "cp -rs \"/repo/builds/$latest_version\"/* . && rm ./game/bin/linuxsteamrt64/cs2 && cp \"/repo/builds/$latest_version/game/bin/linuxsteamrt64/cs2\" ./game/bin/linuxsteamrt64/ && HOME=\"/tmp/cs2home\" ./game/bin/linuxsteamrt64/cs2 -dedicated +map de_dust2" || continue
    rm -rf "./*"
done
