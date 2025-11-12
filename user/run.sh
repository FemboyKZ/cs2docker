#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Create server cfg
rm -f "$server_dir/game/csgo/cfg/server.cfg"
cat <<EOF > "$server_dir/game/csgo/cfg/server.cfg"
hostname "$HOSTNAME"
// hostip 0.0.0.0
// hostport $PORT
sv_password ""
rcon_password "$RCON_PASSWORD"
sv_hibernate_when_empty false
sv_hibernate_postgame_delay 0
sv_tags "$TAGS"
exec fkz-print.cfg
// exec fkz-settings.cfg
exec fkz-logs.cfg
// exec fkz-tv.cfg
EOF

# Make sure necessary directories exist
mkdir -p "$server_dir/game/csgo/addons" "$server_dir/game/csgo/tmp"

# Install layers
install_layer() {
    cp -rf "/layers/$1"/* "$server_dir/game/csgo"
}

install_layer "mm"
rm "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
sed -i "0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/" "$server_dir/game/csgo/gameinfo.gi"

install_layer "accel"
rm "$server_dir/game/csgo/addons/AcceleratorCS2/config.json"

install_layer "kz"
rm "$server_dir/game/csgo/cfg/cs2kz-server-config.txt"

install_layer "cssharp"

# #install_layer "accelcss" # only debug

install_layer "mam"
rm "$server_dir/game/csgo/cfg/multiaddonmanager/multiaddonmanager.cfg"

install_layer "sql_mm"

install_layer "ccvar"

install_layer "cleaner"
rm "$server_dir/game/csgo/addons/cleanercs2/config.cfg"

install_layer "listfix"

install_layer "banfix"

if [[ "${MAPTEST,,}" == "true" || "${MAPTEST,,}" == "yes" || "$MAPTEST" == "1" ]]; then
    install_layer "maptest"
else
    install_layer "cssplugins"

    install_layer "weaponpaints"

    install_layer "statusblocker"

    install_layer "maplist"

    install_layer "configs"
fi

# cs2kz cfg (STUPID TXT FILE)
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
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "apiKey" "$CS2KZ_APIKEY"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "user" "$DB_USER"
modify_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "pass" "$DB_PASS"

# cssharp configs
cssharp_cfg_dir="$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins"

check_file() {
    if [[ ! -f "$1" ]]; then
        echo "Warning: File $1 does not exist, skipping"
        return 1
    fi
    return 0
}

if check_file "$cssharp_cfg_dir/Chat_Logger/Chat_Logger.json"; then
    jq --arg webhook "$DC_CHAT_WEBHOOK?thread_id=$DC_CHAT_THREAD" \
        '.Discord_WebHook = $webhook' \
        "$cssharp_cfg_dir/Chat_Logger/Chat_Logger.json" > "/tmp/Chat_Logger.json"
    mv "/tmp/Chat_Logger.json" "$cssharp_cfg_dir/Chat_Logger/Chat_Logger.json"
fi

if check_file "$cssharp_cfg_dir/ConnectionLogs/ConnectionLogs.json"; then
    jq --arg webhook "$DC_CONNECT_WEBHOOK?thread_id=$DC_CONNECT_THREAD" \
        --arg host "$DB_HOST" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        '.DatabaseHost = $host | .DatabaseUser = $user | .DatabasePassword = $pass | .DatabaseName = $name | .DiscordWebhook = $webhook' \
        "$cssharp_cfg_dir/ConnectionLogs/ConnectionLogs.json" > "/tmp/ConnectionLogs.json"
    mv "/tmp/ConnectionLogs.json" "$cssharp_cfg_dir/ConnectionLogs/ConnectionLogs.json"
fi

if check_file "$cssharp_cfg_dir/CS2ServerList/CS2ServerList.json"; then
    jq --arg apikey "$SVLIST_APIKEY" \
        '."server-api-key" = $apikey' \
        "$cssharp_cfg_dir/CS2ServerList/CS2ServerList.json" > "/tmp/CS2ServerList.json"
    mv "/tmp/CS2ServerList.json" "$cssharp_cfg_dir/CS2ServerList/CS2ServerList.json"
fi

if check_file "$cssharp_cfg_dir/PlayerSettings/PlayerSettings.json"; then
    jq --arg host "$DB_HOST:$DB_PORT" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        '.DatabaseParams.Host = $host | .DatabaseParams.User = $user | .DatabaseParams.Password = $pass | .DatabaseParams.Name = $name' \
        "$cssharp_cfg_dir/PlayerSettings/PlayerSettings.json" > "/tmp/PlayerSettings.json"
    mv "/tmp/PlayerSettings.json" "$cssharp_cfg_dir/PlayerSettings/PlayerSettings.json"
fi

if check_file "$cssharp_cfg_dir/Whitelist/Whitelist.json"; then
    jq --arg apikey "$WS_APIKEY" \
        '.ApiKey = $apikey' \
        "$cssharp_cfg_dir/Whitelist/Whitelist.json" > "/tmp/Whitelist.json"
    mv "/tmp/Whitelist.json" "$cssharp_cfg_dir/Whitelist/Whitelist.json"
fi

if check_file "$server_dir/game/csgo/addons/counterstrikesharp/plugins/AccountDupFinder/Config.json"; then
    jq --arg host "$DB_HOST" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        '.DatabaseHost = $host | .DatabaseUser = $user | .DatabasePassword = $pass | .DatabaseName = $name' \
        "$server_dir/game/csgo/addons/counterstrikesharp/plugins/AccountDupFinder/Config.json" > "/tmp/Config.json"
    mv "/tmp/Config.json" "$server_dir/game/csgo/addons/counterstrikesharp/plugins/AccountDupFinder/Config.json" # this has cfg stored in plugin folder for some reason
fi

if check_file "$cssharp_cfg_dir/Clientprefs/Clientprefs.json"; then
    jq --arg host "$DB_HOST" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        '.DatabaseHost = $host | .DatabaseUsername = $user | .DatabasePassword = $pass | .DatabaseName = $name' \
        "$cssharp_cfg_dir/Clientprefs/Clientprefs.json" > "/tmp/Clientprefs.json"
    mv "/tmp/Clientprefs.json" "$cssharp_cfg_dir/Clientprefs/Clientprefs.json"
fi

if check_file "$cssharp_cfg_dir/WeaponPaints/WeaponPaints.json"; then
    jq --arg host "$DB_HOST" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        --arg site "$SKINSITE_URL" \
        '.DatabaseHost = $host | .DatabaseUser = $user | .DatabasePassword = $pass | .DatabaseName = $name | .Website = $site' \
        "$cssharp_cfg_dir/WeaponPaints/WeaponPaints.json" > "/tmp/WeaponPaints.json"
    mv "/tmp/WeaponPaints.json" "$cssharp_cfg_dir/WeaponPaints/WeaponPaints.json"
fi

if check_file "$cssharp_cfg_dir/CS2-SimpleAdmin/CS2-SimpleAdmin.json"; then
    jq --arg host "$DB_HOST" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --arg name "$GL_DB_NAME" \
        --arg webhook "$DC_ADMIN_WEBHOOK" \
        '.DatabaseConfig.DatabaseHost = $host | .DatabaseConfig.DatabaseUser = $user | .DatabaseConfig.DatabasePassword = $pass | .DatabaseConfig.DatabaseName = $name | .Discord.DiscordLogWebhook = $webhook' \
        "$cssharp_cfg_dir/CS2-SimpleAdmin/CS2-SimpleAdmin.json" > "/tmp/CS2-SimpleAdmin.json"
    mv "/tmp/CS2-SimpleAdmin.json" "$cssharp_cfg_dir/CS2-SimpleAdmin/CS2-SimpleAdmin.json" # theres more webhooks but im too lazy to add them
fi

# I like to use metaplugins.ini to load plugins, so remove all other vdf files to avoid confusion.
find "$server_dir/game/csgo/addons/metamod/" -type f -name "*.vdf" -exec rm -f {} +

# Create metaplugins.ini for metamod
if [[ "${ACCEL,,}" == "true" || "${ACCEL,,}" == "yes" || "$ACCEL" == "1" ]]; then
    echo "ACCEL addons/AcceleratorCS2/AcceleratorCS2" > "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
else
    echo ";ACCEL addons/AcceleratorCS2/AcceleratorCS2" > "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

cat <<EOF >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
;ACCELCSS addons/AcceleratorCSS/bin/linuxsteamrt64/AcceleratorCSS
KZ addons/cs2kz/bin/linuxsteamrt64/cs2kz
CLEANER addons/cleanercs2/cleanercs2
SQLMM addons/sql_mm/bin/linuxsteamrt64/sql_mm
STATUSBLOCKER addons/StatusBlocker/bin/linuxsteamrt64/StatusBlocker
CSS addons/counterstrikesharp/bin/linuxsteamrt64/counterstrikesharp
MAM addons/multiaddonmanager/bin/multiaddonmanager
CCVAR addons/client_cvar_value/client_cvar_value
LISTFIX addons/serverlistplayersfix_mm/bin/linuxsteamrt64/serverlistplayersfix_mm
BANFIX addons/gamebanfix/bin/linuxsteamrt64/gamebanfix
;MENUEXPORT addons/MenusExport/bin/MenusExport
EOF

# Create folders for mounts if not existing
mkdir -p "/mounts/$ID/logs" "/mounts/$ID/addons/counterstrikesharp/logs" "/mounts/$ID/addons/counterstrikesharp/plugins/Chat_Logger/logs" "/mounts/$ID/addons/AcceleratorCS2/dumps" "/mounts/kzdemos" "/mounts/workshop" "mounts/kzreplays"
mkdir -p "$server_dir/game/bin/linuxsteamrt64/steamapps"

install_mount_local() {
    rm -rf "$server_dir/game/csgo/$2"
    ln -s "/mounts/$ID/$1" "$server_dir/game/csgo/$2"
}

install_mount() {
    rm -rf "$server_dir/game/csgo/$2"
    ln -s "/mounts/$1" "$server_dir/game/csgo/$2"
}

install_mount_local "logs" "logs"
install_mount_local "addons/counterstrikesharp/logs" "addons/counterstrikesharp/logs"
install_mount_local "addons/AcceleratorCS2/dumps" "addons/AcceleratorCS2/dumps"
install_mount "kzdemos" "kzdemos"
install_mount "kzreplays" "kzreplays"
install_mount "workshop" "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"

# Run whitelist updater in background if whitelist is enabled
if [[ "${WHITELIST,,}" == "true" || "${WHITELIST,,}" == "yes" || "$WHITELIST" == "1" ]]; then
    install_layer "whitelist"
    cp "/watchdog/fkz/whitelist.txt" "$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins/Whitelist/whitelist.txt"
    /user/updatewl.sh &
elif [[ "${MAPTEST,,}" == "true" || "${MAPTEST,,}" == "yes" || "$MAPTEST" == "1" ]]; then
    echo "" # do nothing
else
    #install_layer "ads"
    #jq --arg region "$REGION" \
    #    '.DefaultLang = $region' \
    #    "$cssharp_cfg_dir/Advertisement/Advertisement.json" > "/tmp/Advertisement.json"
    #mv "/tmp/Advertisement.json" "$cssharp_cfg_dir/Advertisement/Advertisement.json"
    install_mount "addons/counterstrikesharp/plugins/Chat_Logger/logs" "addons/counterstrikesharp/plugins/Chat_Logger/logs"
fi

# Run the server.
"$server_dir/game/cs2.sh" -dedicated -condebug -ip "$IP" -port "$PORT" -authkey "$WS_APIKEY" +sv_setsteamaccount "$GSLT" +map "$MAP" +mapgroup mg_custom +host_workshop_map "$WS_MAP" +exec server.cfg +game_type 3 +game_mode 0 -maxplayers 64 -nohltv
