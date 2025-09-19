#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Create server cfg
cat <<EOF >> "$server_dir/game/csgo/cfg/server.cfg"
hostname "$NAME"
hostip "$IP"
hostport "$PORT"
sv_password "$PASSWORD"
rcon_password "$RCON_PASSWORD"
sv_hibernate_when_empty false
sv_hibernate_postgame_delay 0
sv_tags "$TAGS"
exec fkz-settings.cfg
exec fkz-logs.cfg
// exec fkz-tv.cfg
exec fkz-print.cfg
mp_restartgame 1
EOF

# Make sure necessary directories exist
mkdir -p "$server_dir/game/csgo/addons" "$server_dir/game/csgo/tmp"

# Install layers
install_layer() {
    cp -rf "$root/layers/$1"/* "$server_dir/game/csgo"
}

install_layer "mm"
rm "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
sed -i '0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/' "$server_dir/game/csgo/gameinfo.gi"

install_layer "accel"
rm "$server_dir/game/csgo/addons/AcceleratorCS2/config.json"

install_layer "kz"
rm "$server_dir/game/csgo/cfg/cs2kz-server-config.cfg"

#install_layer "cssharp"

# install_layer "accelcss" # only debug

install_layer "mam"
rm "$server_dir/game/csgo/cfg/multiaddonmanager/multiaddonmanager.cfg"

install_layer "sqlmm"

install_layer "ccvar"

install_layer "cleaner"
rm "$server_dir/game/csgo/addons/cleanercs2/config.cfg"

install_layer "listfix"

install_layer "banfix"

install_layer "configs"

# cs2kz cfg (STUPID TXT FILE)
modify_config() {
    local key="$2"
    local value="$3"
    sed -i "s/\(\"$key\"[[:space:]]*\)\"[^\"]*\"/\1\"$value\"/" "$1"
}
modfiy_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "apiKey" "$CS2KZ_APIKEY"
modfiy_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "user" "$DB_USER"
modfiy_config "$server_dir/game/csgo/cfg/cs2kz-server-config.txt" "pass" "$DB_PASS"

# cssharp configs
cssharp_cfg_dir="$server_dir/game/csgo/addons/counterstrikesharp/configs/plugins"

jq ".WebHookURL = '$DC_CHAT_WEBHOOK?thread_id=$DC_CHAT_THREAD'" "$cssharp_cfg_dir/Chat_Logger/Chat_Logger.json"

jq ".DiscordWebhook = '$DC_CONNECT_WEBHOOK?thread_id=$DC_CONNECT_THREAD'" "$cssharp_cfg_dir/ConnectionLogs/ConnectionLogs.json"

jq ".GeneralConfig.ServerIP = '$IP_DOMAIN:$PORT' | .EmbedConfig.Title = '$HOSTNAME'" "$cssharp_cfg_dir/DiscordStatus/DiscordStatus.json"
jq ".WebhookConfig.StatusWebhookURL = '$DC_STATUS_MSG_WEBHOOK' | .WebhookConfig.StatusWebhookID = '$DC_STATUS_MSG_ID'" "$cssharp_cfg_dir/DiscordStatus/DiscordStatus.json"

jq ".server-api-key = '$SVLIST_APIKEY'" "$cssharp_cfg_dir/CS2ServerList/CS2ServerList.json"

jq ".DatabaseParams.User = '$DB_USER' | .DatabaseParams.Password = '$DB_PASS' | .DatabaseParams.Name = '$DB_NAME'" "$cssharp_cfg_dir/PlayerSettings/PlayerSettings.json"

jq ".ApiKey = '$WS_APIKEY'" "$cssharp_cfg_dir/Whitelist/Whitelist.json"

# I like to use metaplugins.ini (created in cs2server/configs.sh) to load plugins, so remove all other vdf files to avoid confusion.
find "$server_dir/game/csgo/addons/metamod/" -type f -name "*.vdf" -exec rm -f {} +

# Create metaplugins.ini for metamod
if [[ "${ACCEL,,}" == "true" || "${ACCEL,,}" == "yes" || "$ACCEL" == "1" ]]; then
    echo "ACCEL addons/AcceleratorCS2/AcceleratorCS2" >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
else
    echo ";ACCEL addons/AcceleratorCS2/AcceleratorCS2" >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

cat <<EOF >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
;ACCELCSS addons/AcceleratorCSS/bin/linuxsteamrt64/AcceleratorCSS
KZ addons/cs2kz/bin/linuxsteamrt64/cs2kz
CLEANER addons/cleanercs2/cleanercs2
SQLMM addons/sql_mm/bin/linuxsteamrt64/sql_mm
CSS addons/counterstrikesharp/bin/linuxsteamrt64/counterstrikesharp
MAM addons/multiaddonmanager/bin/multiaddonmanager
CCVAR addons/client_cvar_value/client_cvar_value
LISTFIX addons/serverlistplayersfix_mm/bin/linuxsteamrt64/serverlistplayersfix_mm
;VOICEFIX addons/CS2VoiceFix/CS2VoiceFix
;GOTVFIX addons/GOTVCrashFix/GOTVCrashFix
BANFIX addons/gamebanfix/bin/linuxsteamrt64/gamebanfix
;MENUEXPORT addons/MenusExport/bin/MenusExport
EOF

# Create symlinks for mounts
if [[ ! -d "$root/mounts/$ID" ]]; then
    mkdir -p "$root/mounts/$ID/logs" "$root/mounts/$ID/addons/counterstrikesharp/logs" "$root/mounts/$ID/addons/counterstrikesharp/plugins/Chat_logger/logs"
fi

install_mount() {
    rm -rf "$server_dir/game/csgo/$2"
    ln -s "$root/mounts/$ID/$1" "$server_dir/game/csgo/$2"
}

install_mount "logs" "logs"
install_mount "addons/counterstrikesharp/logs" "addons/counterstrikesharp/logs"
install_mount "addons/counterstrikesharp/plugins/Chat_logger/logs" "addons/counterstrikesharp/plugins/Chat_logger/logs"

# Run whitelist updater in background if whitelist is enabled
if [[ "${WHITELIST,,}" == "true" || "${WHITELIST,,}" == "yes" || "$WHITELIST" == "1" ]]; then
    install_layer "whitelist"
    /user/updatewl.sh &
fi

# Run the server.
"$server_dir/game/bin/linuxsteamrt64/cs2" -dedicated -ip "$IP" -port "$PORT" -authkey "$WS_APIKEY" +sv_setsteamaccount "$GSLT" +map "$MAP" +mapgroup mg_custom +host_workshop_map "$WS_MAP" +exec server.cfg +game_type 3 +game_mode 0 -maxplayers 64 -nohltv
