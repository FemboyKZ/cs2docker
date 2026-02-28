#!/bin/bash

set -ueEo pipefail

install_github_release() {
    local owner="$1"
    local repo="$2"
    local asset_pattern="$3"
    local install_dir="$4"
    local version_file="/watchdog/${repo}_version.txt"

    local release_json
    release_json=$(curl -sSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$owner/$repo/releases?per_page=1")

    if ! echo "$release_json" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "ERROR: GitHub API error for $owner/$repo:"
        echo "$release_json" | jq -r '.message // .'
        return 1
    fi

    release_json=$(echo "$release_json" | jq '.[0]')

    local latest
    latest=$(echo "$release_json" | jq -r '.tag_name')

    local installed=""
    if [[ -f "$version_file" ]]; then
        installed=$(cat "$version_file")
    fi

    mkdir -p "$install_dir"

    if [[ "$latest" != "$installed" ]]; then
        echo "Installing $repo: $latest"
        local asset_url
        asset_url=$(echo "$release_json" | jq -r --arg pat "$asset_pattern" \
            '.assets[] | select((.name | test($pat)) and (.name | test("upgrade") | not)) | .browser_download_url')

        if [[ -z "$asset_url" ]]; then
            echo "ERROR: No asset matched pattern '$asset_pattern' for $owner/$repo"
            echo "Available assets:"
            echo "$release_json" | jq -r '.assets[].name'
            return 1
        fi

        local tmp_file="/tmp/${repo}_${latest}"
        curl -sSL "$asset_url" -o "$tmp_file"

        local file_type
        file_type=$(file --brief --mime-type "$tmp_file")

        case "$file_type" in
            application/zip)
                unzip -o -q "$tmp_file" -d "$install_dir"
                ;;
            application/gzip|application/x-gzip)
                tar -xz --overwrite --no-same-permissions -f "$tmp_file" -C "$install_dir"
                ;;
            application/x-tar)
                tar -x --overwrite --no-same-permissions -f "$tmp_file" -C "$install_dir"
                ;;
            *)
                echo "ERROR: Unknown file type '$file_type' for $repo asset"
                rm -f "$tmp_file"
                return 1
                ;;
        esac

        rm -f "$tmp_file"
        echo "$latest" > "$version_file"
    else
        echo "$repo already up to date: $installed"
    fi
}

install_metamod() {
    local version_file="/watchdog/mm_version.txt"
    local latest
    latest=$(curl -sSL "https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux")

    local installed=""
    if [[ -f "$version_file" ]]; then
        installed=$(cat "$version_file")
    fi

    if [[ "$latest" != "$installed" ]]; then
        echo "Installing metamod: $latest"
        mkdir -p "/layers/mm"
        curl -sSL "https://mms.alliedmods.net/mmsdrop/2.0/$latest" \
            | tar -xz --overwrite --no-same-permissions -C "/layers/mm"
        echo "$latest" > "$version_file"
    else
        echo "Metamod already up to date: $installed"
    fi
}

update_plugins() {
    install_metamod
    install_github_release "Source2ZE" "AcceleratorCS2" "addons" "/layers/accel/addons"
    install_github_release "KZGlobalTeam" "cs2kz-metamod" "linux-master\.tar\.gz$" "/layers/kz"
    install_github_release "roflmuffin" "CounterStrikeSharp" "with-runtime-linux" "/layers/cssharp"
    install_github_release "Source2ZE" "MultiAddonManager" "linux" "/layers/mam"
    install_github_release "zer0k-z" "sql_mm" "linux" "/layers/sql_mm"
    install_github_release "komashchenko" "ClientCvarValue" "linux" "/layers/ccvar"
    install_github_release "Source2ZE" "CleanerCS2" "CleanerCS2" "/layers/cleaner/addons"
    install_github_release "Source2ZE" "ServerListPlayersFix" "linux" "/layers/listfix"
    install_github_release "Cruze03" "GameBanFix" "linux" "/layers/banfix"
    install_github_release "zer0k-z" "wscleaner" "linux" "/layers/wscleaner"
}

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

    update_plugins || true
done
