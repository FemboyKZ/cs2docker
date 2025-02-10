#!/bin/bash

fetch_latest_cs2_version() {
    local api_url="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1?version=0&format=json&appid=730"
    local api_response; api_response=$(curl -sf "$api_url") || return 1
    local latest_version; latest_version=$(jq -re '.response.required_version | select(type == "number")' <<< "$api_response") || return 1
    
    echo "$latest_version"
    return 0
}

update_cs2() {
    # Download CS2 to /repo/install
    steamcmd +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +@bMetricsEnabled 0 +force_install_dir "/repo/install" +login anonymous +app_update 730 +quit > /dev/null || return 1
    
    # Check which version we just installed
    local installed_version; installed_version=$(grep PatchVersion= "/repo/install/game/csgo/steam.inf" | tr -cd '0-9') || return 1
    echo "$installed_version" 

    # We already have this version
    [ -d "/repo/builds/$installed_version" ] && return 1

    # Hard symlink the files from /repo/install to /repo/tmp, then rename /repo/tmp to /repo/builds/????? so servers only see it after it's finished
    cp -rl "/repo/install" "/repo/tmp" || return 1
    mv "/repo/tmp" "/repo/builds/$installed_version" || return 1

    return 0
}

main() {
    for (( first=1;; first=0 )); do
        [ $first -eq 0 ] && sleep 10
        
        # The temporary directory might exist if update_cs2 fails
        rm -rf "/repo/tmp" || continue

        local latest_version; latest_version=$(fetch_latest_cs2_version) || continue

        # Remove outdated CS2 builds that are not being used by any server
        find "/repo/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$latest_version" -exec flock -nx "{}" --command "rm -rf {}" \;

        # Update CS2 if we don't have the latest version
        [ ! -d "/repo/builds/$latest_version" ] && update_cs2
    done
}

mkdir -p "/repo/builds" || exit 1
main
