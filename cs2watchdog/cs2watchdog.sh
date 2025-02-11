#!/bin/bash

set -ueEo pipefail

fetch_latest_cs2_version() {
    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?version=0&format=json&appid=730"
    curl -sf $api_url | jq -re ".response.required_version | select(type == \"number\")"
}

update_cs2() {
    # Download CS2 to /repo/install
    HOME="/repo/steamcmd" "/repo/steamcmd/steamcmd.sh" +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +@bMetricsEnabled 0 +force_install_dir "/repo/install" +login anonymous +app_update 730 validate +quit 1>&2

    # Check which version we just installed
    local installed_version="$(grep PatchVersion= "/repo/install/game/csgo/steam.inf" | tr -cd "0-9")"

    # Return if we already have this version
    [ ! -d "/repo/builds/$installed_version" ]

    # Hard symlink the files from /repo/install to /repo/tmp, then rename /repo/tmp to /repo/builds/????? so servers only see it after it's finished
    cp -rl "/repo/install" "/repo/tmp"
    mv "/repo/tmp" "/repo/builds/$installed_version"
}

# Download SteamCMD
if [ ! -d "/repo/steamcmd" ]; then
    mkdir -p "/tmp/steamcmd"
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C "/tmp/steamcmd"
    mv "/tmp/steamcmd" "/repo/steamcmd"
fi

mkdir -p "/repo/builds"

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    # The temporary directory might exist if update_cs2 fails
    rm -rf "/repo/tmp"

    latest_version="$(fetch_latest_cs2_version)" || continue

    # Remove outdated CS2 builds that are not being used by any server
    find "/repo/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$latest_version" -exec flock -nx "{}/.lockfile" --command "rm -rf \"{}\"" \; || true

    # Update CS2 if we don't have the latest version
    if [ ! -d "/repo/builds/$latest_version" ]; then
        update_cs2 || true
    fi
done
