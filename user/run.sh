#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm -rf "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Cleanup old addons to prevent stale files from previous versions.
rm -rf "$server_dir/game/csgo/addons"

# Make sure necessary directories exist
mkdir -p "$server_dir/game/csgo/addons" "$server_dir/game/csgo/cfg" "$server_dir/game/csgo/tmp"
mkdir -p "/mounts/$ID/workshop" "/mounts/kzreplays" "/mounts/$ID" "/mounts/configs" "/mounts/configs/counterstrikesharp"
mkdir -p "/mounts/$ID/logs" "/mounts/$ID/logs/counterstrikesharp" "/mounts/$ID/dumps"
mkdir -p "$server_dir/game/bin/linuxsteamrt64/steamapps"

# Helper functions
install_layer() {
    local name="$1"
    local subdir="${2:-}"
    local out_subdir="${3:-}"
    local latest_file="/watchdog/layers/$name/latest.txt"
    local base
    if [[ -f "$latest_file" ]]; then
        local ver
        ver=$(cat "$latest_file")
        base="/watchdog/layers/$name/builds/$ver"
    else
        base="/layers/$name"
    fi
    if [[ -n "$subdir" ]]; then
        for src in "$base"/$subdir; do
            cp -rf "$src"/* "$server_dir/game/csgo${out_subdir:+/$out_subdir}"
        done
    else
        cp -rf "$base"/* "$server_dir/game/csgo${out_subdir:+/$out_subdir}"
    fi
}

install_mount() {
    rm -rf "$server_dir/game/csgo/$2"
    mkdir -p "$(dirname "$server_dir/game/csgo/$2")"
    ln -s "/mounts/$1" "$server_dir/game/csgo/$2"
}

modify_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    local escaped_value=$(printf '%s' "$value" | sed -e 's/[\x00-\x1F\x7F]/\\&/g' -e 's/[\/&]/\\&/g')
    if grep -q "\"$key\"" "$file"; then
        sed -i "s/\(\"$key\"[[:space:]]*\)\"[^\"]*\"/\1\"$escaped_value\"/" "$file"
    else
        echo "Warning: Key '$key' not found in $file"
    fi
}

install_github_release() {
    local owner="$1"
    local repo="$2"
    local asset_pattern="$3"
    local install_dir="$4"
    local subdir="${5:-*}" # subdir within extracted archive to copy from; * = skip wrapper dir
    local version_file="/watchdog/gh/${repo}/version.txt"
    local cache_dir="/watchdog/gh/${repo}/files"
    local tmp_dir="/tmp/gh_${repo}"
    local tmp_archive="/tmp/gh_${repo}.archive"

    local release_json
    release_json=$(curl -sSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$owner/$repo/releases?per_page=1")

    # Check if we got an array back, otherwise it's an API error
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

    if [[ "$latest" != "$installed" ]]; then
        echo "Installing $repo $latest..."

        local asset_url
        asset_url=$(echo "$release_json" | jq -r --arg pat "$asset_pattern" \
            '.assets[] | select((.name | test($pat)) and (.name | test("upgrade") | not)) | .browser_download_url')

        if [[ -z "$asset_url" ]]; then
            echo "ERROR: No asset matched pattern '$asset_pattern' for $owner/$repo"
            echo "Available assets:"
            echo "$release_json" | jq -r '.assets[].name'
            return 1
        fi

        rm -rf "$tmp_dir"
        mkdir -p "$tmp_dir"
        curl -sSL "$asset_url" -o "$tmp_archive"

        case "$asset_url" in
            *.zip)
                unzip -o -q "$tmp_archive" -d "$tmp_dir"
                ;;
            *.tar.gz|*.tgz|*.tar.xz|*.tar)
                tar -x --no-same-permissions -f "$tmp_archive" -C "$tmp_dir"
                ;;
            *)
                echo "ERROR: Unknown file extension for $repo: $asset_url"
                rm -f "$tmp_archive"
                rm -rf "$tmp_dir"
                return 1
                ;;
        esac || { rm -f "$tmp_archive"; rm -rf "$tmp_dir"; return 1; }

        rm -f "$tmp_archive"

        # Extract into persistent cache, replacing any previous version.
        rm -rf "$cache_dir"
        mkdir -p "$cache_dir"
        for src in "$tmp_dir"/${subdir:-*}; do
            if [[ -d "$src" ]]; then
                cp -rf "$src"/* "$cache_dir/"
            else
                cp -rf "$src" "$cache_dir/"
            fi
        done

        rm -rf "$tmp_dir"
        echo "$latest" > "$version_file"
        echo "$repo installed: $latest"
    else
        echo "$repo already up to date: $installed"
    fi

    # Always copy from cache into the (freshly built) server dir.
    rm -rf "$install_dir"
    mkdir -p "$install_dir"
    find "$cache_dir" -maxdepth 1 -mindepth 1 -exec cp -rf {} "$install_dir/" \;
}

# install MetadMod
install_layer "mm"
sed -i "0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/" "$server_dir/game/csgo/gameinfo.gi"

# Install MM Plugins
install_layer "accel" "" "addons"
install_layer "kz"
install_layer "cssharp"
install_layer "mam"
install_layer "sql_mm"
install_layer "ccvar"
install_layer "cleaner" "" "addons"
install_layer "listfix"
install_layer "banfix"
install_layer "cs2admin"

# Install CSS plugins
install_layer "autorestart"
cat <<EOF > "$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins/AutoRestart.json"
{
  "daily_restart_time": "$RESTART_TIME",
  "ConfigVersion": 1
}
EOF

# Maptest or FKZ plugins
if [[ "${MAPTEST,,}" == "true" ]]; then
    install_layer "maptest"
    install_layer "wscleaner"
else
    # Misc plugins
    # Minor plugins rarely update, so we can just check once at startup

    install_layer "cs2menumanager"

    #install_github_release "FemboyKZ" "cs2-rockthevote" "RockTheVote" "/layers/rtv/RockTheVote"
    install_layer "rtv"

    #install_github_release "FemboyKZ" "cs2-simple-guns-menu" "SimpleGunMenuPlugin" "/layers/guns/SimpleGunMenuPlugin"
    install_layer "guns" "" "addons/counterstrikesharp/plugins"

    #install_github_release "FemboyKZ" "anti-fun" "cs2" "/layers/antifun"
    install_layer "antifun"

    #install_github_release "FemboyKZ" "CustomStatus" "CStatus" "/layers/cstatus"
    install_layer "cstatus"

    #install_layer "htmlfix"
    install_layer "motdfix"

    # CSS Deps
    #install_layer "playersettings"
    #install_layer "anybaselib"
    #install_layer "menumanager"

    # WeaponPaints
    #install_layer "weaponpaints" "" "addons/counterstrikesharp/plugins"
    #cp -rf "$server_dir/game/csgo/addons/counterstrikesharp/plugins/gamedata"/. "$server_dir/game/csgo/addons/counterstrikesharp/gamedata/"
    #rm -rf "$server_dir/game/csgo/addons/counterstrikesharp/plugins/gamedata"
fi

# Install whitelist if enabled
if [[ "${WHITELIST,,}" = "true" ]]; then
    install_layer "whitelist"
    install_mount "configs/Whitelist" "addons/counterstrikesharp/configs/plugins/Whitelist"
fi

# Cleanup cfg files before installing our own, to prevent stale configs from previous versions.
rm -rf "$server_dir/game/csgo/addons/AcceleratorCS2/config.json"
rm -rf "$server_dir/game/csgo/cfg/multiaddonmanager/multiaddonmanager.cfg"
rm -rf "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
rm -rf "$server_dir/game/csgo/addons/cleanercs2/config.cfg"
rm -rf "$server_dir/game/csgo/cfg/server.cfg"
find "$server_dir/game/csgo/addons/metamod/" -type f -name "*.vdf" -exec rm -f {} +

# Create metaplugins.ini for metamod
if [[ "${ACCEL,,}" == "cs2" || "${ACCEL,,}" == "true" ]]; then
    echo "ACCEL addons/AcceleratorCS2/AcceleratorCS2" > "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

if [[ "${MAPTEST,,}" == "true" ]]; then
    echo "WSCLEANER addons/wscleaner/bin/wscleaner" > "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

cat <<EOF >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
KZ addons/cs2kz/bin/linuxsteamrt64/cs2kz
CLEANER addons/cleanercs2/cleanercs2
SQLMM addons/sql_mm/bin/linuxsteamrt64/sql_mm
CSS addons/counterstrikesharp/bin/linuxsteamrt64/counterstrikesharp
MAM addons/multiaddonmanager/bin/multiaddonmanager
CCVAR addons/client_cvar_value/client_cvar_value
LISTFIX addons/serverlistplayersfix_mm/bin/linuxsteamrt64/serverlistplayersfix_mm
BANFIX addons/gamebanfix/bin/linuxsteamrt64/gamebanfix
EOF

# Create server cfg
cat <<EOF > "$server_dir/game/csgo/cfg/server.cfg"
hostname "$HOSTNAME"
sv_password ""
rcon_password "$RCON_PASSWORD"
sv_hibernate_when_empty false
sv_hibernate_postgame_delay 0
sv_tags "$TAGS"
mp_autokick 0
exec fkz-print.cfg
// exec fkz-settings.cfg
// exec fkz-logs.cfg
// exec fkz-tv.cfg
EOF

# Mount static configs we create/setup manually, so they persist across plugin updates.
install_mount "configs/maplist.txt" "cfg/maplist.txt"
install_mount "configs/gamemodes_server.txt" "gamemodes_server.txt"
install_mount "configs/gamemodes_custom_server.cfg" "cfg/gamemodes_custom_server.cfg"
#install_mount "configs/fkz-settings.cfg" "cfg/fkz-settings.cfg"
install_mount "configs/fkz-print.cfg" "cfg/fkz-print.cfg"
#install_mount "configs/fkz-logs.cfg" "cfg/fkz-logs.cfg"
#install_mount "configs/fkz-tv.cfg" "cfg/fkz-tv.cfg"

install_mount "configs/AcceleratorCS2/config.json" "addons/AcceleratorCS2/config.json"
install_mount "configs/multiaddonmanager/multiaddonmanager.cfg" "cfg/multiaddonmanager/multiaddonmanager.cfg"

# cssharp configs
cssharp_cfg_dir="$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins"
install_mount "configs/counterstrikesharp" "addons/counterstrikesharp/configs"

# cs2kz cfg (STUPID TXT FILE)
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "defaultMode" "Vanilla"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "defaultTimeLimit" "600.0"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "chatPrefix" "{orchid}FKZ {grey}|{default}"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "overridePlayerChat" "true"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "driver" "mysql"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "host" "$DB_HOST"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "port" "$DB_PORT"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "database" "$GL_DB_NAME"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "apiKey" "$CS2KZ_APIKEY"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "user" "$DB_USER"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "pass" "$DB_PASS"

# Mount logs
install_mount "$ID/logs" "logs"
install_mount "$ID/logs/counterstrikesharp" "addons/counterstrikesharp/logs"
install_mount "$ID/dumps" "addons/AcceleratorCS2/dumps"
# Mount replays
install_mount "kzreplays" "kzreplays"

# Mount workshop
rm -rf "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"
ln -s "/mounts/$ID/workshop" "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"

# Write MOTD and WebAPI key
rm -rf "$server_dir/game/csgo/motd.txt"
echo "$MOTD" > "$server_dir/game/csgo/motd.txt"

rm -rf "$server_dir/game/csgo/webapi_authkey.txt"
echo "$WS_APIKEY" > "$server_dir/game/csgo/webapi_authkey.txt"

# Run the server.
"$server_dir/game/cs2.sh" -dedicated -condebug -disable_workshop_command_filtering -ip "$IP" -port "$PORT" -authkey "$WS_APIKEY" +sv_setsteamaccount "$GSLT" +map "$MAP" +host_workshop_map "$WS_MAP" +exec server.cfg -maxplayers 64 -nohltv
