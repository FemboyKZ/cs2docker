#!/bin/bash

set -ueEo pipefail

fetch_latest_cs2_version() {
    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?version=0&format=json&appid=730"
    curl -sf $api_url | jq -re ".response.required_version | select(type == \"number\")"
}

update_cs2() {
    # Download CS2 to /watchdog/cs2/install
    HOME="/watchdog/steamcmd" /watchdog/steamcmd/steamcmd.sh +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +@bMetricsEnabled 0 +force_install_dir "/watchdog/cs2/install" +login anonymous +app_update 730 validate +quit 1>&2

    # Check which version we just installed
    local installed_version="$(grep PatchVersion= "/watchdog/cs2/install/game/csgo/steam.inf" | tr -cd "0-9")"

    # Return if we already have this version
    [ ! -d "/watchdog/cs2/builds/$installed_version" ]

    # Hard symlink the files from /watchdog/cs2/install to /watchdog/.tmp, then rename /watchdog/.tmp to /watchdog/cs2/builds/????? so it's atomic.
    # Must use a tmp directory inside of the /watchdog because symlinks don't work across filesystems.
    cp -rl "/watchdog/cs2/install" "/watchdog/.tmp"
    mv "/watchdog/.tmp" "/watchdog/cs2/builds/$installed_version"

    # Store the version in latest.txt so servers can detect an update
    rm "/tmp/latest.txt"
    echo "$installed_version" > "/tmp/latest.txt"
    mv "/tmp/latest.txt" "/watchdog/cs2/latest.txt"
}

# Download SteamCMD
if [ ! -d "/watchdog/steamcmd" ]; then
    mkdir -p "/tmp/steamcmd"
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - -C "/tmp/steamcmd"
    mv "/tmp/steamcmd" "/watchdog/steamcmd"
fi

mkdir -p "/watchdog/cs2/builds"

for (( first=1;; first=0 )); do
    [ $first -eq 0 ] && sleep 10

    # The temporary directory might exist if update_cs2 fails
    rm -rf "/watchdog/.tmp"

    latest_version="$(fetch_latest_cs2_version)" || continue

    # Remove outdated CS2 builds that are not being used by any server
    find "/watchdog/cs2/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$latest_version" -exec flock -nx "{}/.lockfile" --command "rm -rf \"{}\"" \; || true

    # Update CS2 if we don't have the latest version
    if [ ! -d "/watchdog/cs2/builds/$latest_version" ]; then
        update_cs2 || true
    fi
done
