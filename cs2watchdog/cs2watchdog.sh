#!/bin/bash

set -ueEo pipefail

install_github_release() {
    local owner="$1"
    local repo="$2"
    local asset_pattern="$3"
    local name="$4"  # layer name (key for builds dir)
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"

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

    if [ -d "$builds_dir/$latest" ] && [ -n "$(ls -A "$builds_dir/$latest")" ]; then
        return 0
    fi

    echo "Installing $name: $latest"
    local asset_url
    asset_url=$(echo "$release_json" | jq -r --arg pat "$asset_pattern" \
        '[.assets[] | select((.name | test($pat)) and (.name | test("upgrade") | not))][0].browser_download_url // empty')

    if [[ -z "$asset_url" ]]; then
        echo "ERROR: No asset matched pattern '$asset_pattern' for $owner/$repo"
        echo "Available assets:"
        echo "$release_json" | jq -r '.assets[].name'
        return 1
    fi

    local tmp_archive="/tmp/${name}_${latest}"
    rm -f "$tmp_archive"
    if ! curl -fsSL "$asset_url" -o "$tmp_archive"; then
        echo "ERROR: Failed to download asset for $name: $asset_url"
        rm -f "$tmp_archive"
        return 1
    fi

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    case "$asset_url" in
        *.zip)
            unzip -o -q "$tmp_archive" -d "$tmp_dir"
            ;;
        *.tar.gz|*.tgz|*.tar.xz|*.tar)
            tar -x --no-same-permissions -f "$tmp_archive" -C "$tmp_dir"
            ;;
        *)
            echo "ERROR: Unknown file extension for $name: $asset_url"
            rm -f "$tmp_archive"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac || { rm -f "$tmp_archive"; rm -rf "$tmp_dir"; return 1; }

    rm -f "$tmp_archive"
    mkdir -p "$builds_dir"
    mv "$tmp_dir" "$builds_dir/$latest"

    echo "$latest" > "/tmp/layer_latest.txt"
    mv "/tmp/layer_latest.txt" "$latest_file"
}

install_metamod() {
    local name="mm"
    local builds_dir="/watchdog/layers/$name/builds"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local tmp_dir="/watchdog/layers/.tmp"

    local latest
    latest=$(curl -sSL "https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux")

    if [ -d "$builds_dir/$latest" ] && [ -n "$(ls -A "$builds_dir/$latest")" ]; then
        return 0
    fi

    echo "Installing metamod: $latest"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    curl -sSL "https://mms.alliedmods.net/mmsdrop/2.0/$latest" \
        | tar -xz --no-same-permissions -C "$tmp_dir"

    mkdir -p "$builds_dir"
    mv "$tmp_dir" "$builds_dir/$latest"

    echo "$latest" > "/tmp/layer_latest.txt"
    mv "/tmp/layer_latest.txt" "$latest_file"
}

update_plugins() {
    local layer_names=("mm" "accel" "kz" "cssharp" "mam" "sql_mm" "ccvar" "cleaner" "listfix" "banfix" "wscleaner")

    rm -rf "/watchdog/layers/.tmp"

    install_metamod
    install_github_release "Source2ZE"       "AcceleratorCS2"       "addon"                  "accel"
    install_github_release "KZGlobalTeam"    "cs2kz-metamod"        'linux-master\.tar\.gz$' "kz"
    install_github_release "roflmuffin"      "CounterStrikeSharp"   "with-runtime-linux"     "cssharp"
    install_github_release "Source2ZE"       "MultiAddonManager"    "linux"                  "mam"
    install_github_release "zer0k-z"         "sql_mm"               "linux"                  "sql_mm"
    install_github_release "komashchenko"    "ClientCvarValue"      "linux"                  "ccvar"
    install_github_release "Source2ZE"       "CleanerCS2"           "CleanerCS2"             "cleaner"
    install_github_release "Source2ZE"       "ServerListPlayersFix" "linux"                  "listfix"
    install_github_release "Cruze03"         "GameBanFix"           "linux"                  "banfix"
    install_github_release "zer0k-z"         "wscleaner"            "linux"                  "wscleaner"

    (
        flock -nx 200 || exit 0
        for _cleanup_name in "${layer_names[@]}"; do
            _cleanup_latest_file="/watchdog/layers/$_cleanup_name/latest.txt"
            [ -f "$_cleanup_latest_file" ] || continue
            _cleanup_latest=$(cat "$_cleanup_latest_file")
            find "/watchdog/layers/$_cleanup_name/builds" -mindepth 1 -maxdepth 1 -type d ! -name "$_cleanup_latest" \
                -exec rm -rf {} + 2>/dev/null || true
        done
    ) 200>/watchdog/layers/.lockfile || true
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
    [ $first -eq 0 ] && sleep 30

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
