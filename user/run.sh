#!/bin/bash
trap '' SIGINT
set -ueEo pipefail

echo "Build version: $build_ver"
echo "Restart time: $RESTART_TIME"
echo "Build dir: $build_dir"
echo "Server name: ${HOSTNAME:-}"

export daily_restart_time="$RESTART_TIME"
export discord_webhook="$DC_RESTART_WEBHOOK"
export server_name="${HOSTNAME:-}"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm -rf "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Cleanup old addons to prevent stale files from previous versions.
rm -rf "$server_dir/game/csgo/addons"

# Make sure necessary directories exist
mkdir -p "$server_dir/game/csgo/addons" "$server_dir/game/csgo/cfg" "$server_dir/game/csgo/tmp"
mkdir -p "/mounts/$ID/workshop" "/mounts/kzreplays" "/mounts/$ID" "/mounts/configs"
mkdir -p "/mounts/$ID/logs" "/mounts/$ID/logs/kz" "/mounts/$ID/dumps"
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

install_cfg() {
    rm -rf "$server_dir/game/csgo/$2"
    mkdir -p "$(dirname "$server_dir/game/csgo/$2")"
    cp "/watchdog/layers/cfg/builds/$(cat /watchdog/layers/cfg/latest.txt)/$1" "$server_dir/game/csgo/$2"
}

modify_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    local escaped_value=$(printf '%s' "$value" | sed -e 's/[\x00-\x1F\x7F]/\\&/g' -e 's/[\/&]/\\&/g')
    if grep -Eq "^[[:space:]]*\"?$key\"?[[:space:]]" "$file"; then
        sed -Ei "s/^([[:space:]]*\"?$key\"?[[:space:]]+)\"[^\"]*\"/\1\"$escaped_value\"/" "$file"
    else
        echo "Warning: Key '$key' not found in $file"
    fi
}

# install MetadMod
install_layer "mm"
sed -i "0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/" "$server_dir/game/csgo/gameinfo.gi"

# Install MM Plugins
install_layer "accel"
install_layer "kz"
install_layer "mam"
install_layer "sql_mm"
install_layer "ccvar"
install_layer "cleaner"
install_layer "listfix"
install_layer "beamfix"
install_layer "spamfix"
install_layer "banfix"
install_layer "fkzapi"
install_layer "cs2admin"
install_layer "cs2menus"
install_layer "cs2whitelist"
install_layer "cs2rockthevote"
install_layer "autorestart"

#install_layer "test"

# Maptest or FKZ plugins
if [[ "${MAPTEST,,}" == "true" ]]; then
    install_layer "maptest"
    install_layer "wscleaner"
fi

# Cleanup cfg files before installing our own, to prevent stale configs from previous versions.
rm -rf "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
rm -rf "$server_dir/game/csgo/cfg/server.cfg"
find "$server_dir/game/csgo/addons/metamod/" -type f -name "*.vdf" -exec rm -f {} +

# Create metaplugins.ini for metamod
if [[ "${MAPTEST,,}" == "true" ]]; then
    echo "WSCLEANER addons/wscleaner/bin/wscleaner" > "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

cat <<EOF >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
ACCEL addons/AcceleratorCS2/AcceleratorCS2
KZ addons/cs2kz/bin/linuxsteamrt64/cs2kz
CLEANER addons/cleanercs2/cleanercs2
SQLMM addons/sql_mm/bin/linuxsteamrt64/sql_mm
MAM addons/multiaddonmanager/bin/multiaddonmanager
CCVAR addons/client_cvar_value/client_cvar_value
LISTFIX addons/serverlistplayersfix_mm/bin/linuxsteamrt64/serverlistplayersfix_mm
BANFIX addons/gamebanfix/bin/linuxsteamrt64/gamebanfix
FKZ addons/fkz-api/bin/linuxsteamrt64/fkz-api
MENU addons/cs2menus/bin/linuxsteamrt64/cs2menus
ADMIN addons/cs2admin/bin/linuxsteamrt64/cs2admin
RTV addons/cs2rockthevote/bin/linuxsteamrt64/cs2rockthevote
RESTART addons/autorestart/bin/linuxsteamrt64/autorestart
BEAM addons/beam_crash_fix/bin/linuxsteamrt64/beam_crash_fix
SPAM addons/console_spam_fix/bin/linuxsteamrt64/console_spam_fix
;MENUTEST addons/cs2menus_consumer/bin/linuxsteamrt64/cs2menus_consumer
EOF

# Install whitelist if enabled
if [[ "${WHITELIST,,}" = "true" ]]; then
    echo "WHITELIST addons/cs2whitelist/bin/linuxsteamrt64/cs2whitelist" >> "$server_dir/game/csgo/addons/metamod/metaplugins.ini"
fi

# Create server cfg
cat <<EOF > "$server_dir/game/csgo/cfg/server.cfg"
hostname "$HOSTNAME"
sv_password ""
rcon_password "$RCON_PASSWORD"
sv_hibernate_when_empty true
sv_hibernate_postgame_delay 5
sv_tags "cs2kz, kz, kreedz, fkz, ckz, kzt, skz, vnl"
mp_autokick 0
kz_profile_clantag_enabled false
exec fkz-print.cfg
EOF

# Plugin configs
if [[ ("$REGION" = "EU" && "$ID" = "fkz-7") || ("$REGION" = "NA" && "$ID" = "fkz-5") ]]; then
    install_cfg "CS2/maplistmv.txt" "cfg/maplist.txt"
elif [[ ("$REGION" = "EU" && "$ID" = "fkz-8") || ("$REGION" = "NA" && "$ID" = "fkz-6") ]]; then
    install_cfg "CS2/maplisteasy.txt" "cfg/maplist.txt"
else
    install_cfg "CS2/maplist.txt" "cfg/maplist.txt"
fi

install_cfg "CS2/motd.txt" "motd.txt"
install_cfg "CS2/gamemodes_custom.cfg" "cfg/gamemodes_custom.cfg"
install_cfg "CS2/gamemodes_custom.cfg" "cfg/gamemodes_custom_server.cfg"

# FKZ
install_cfg "CS2/fkz-print.cfg" "cfg/fkz-print.cfg"
install_cfg "CS2/fkz-api/core.cfg" "cfg/fkz-api/core.cfg"
# install_cfg "CS2/fkz-logs.cfg" "cfg/fkz-logs.cfg"
# install_cfg "CS2/fkz-tv.cfg" "cfg/fkz-tv.cfg"

# Core
install_cfg "CS2/cs2menus/core.cfg" "cfg/cs2menus/core.cfg"
install_cfg "CS2/cs2admin/core.cfg" "cfg/cs2admin/core.cfg"
install_cfg "CS2/cs2rtv/core.cfg" "cfg/cs2rtv/core.cfg"
install_cfg "CS2/cs2whitelist/core.cfg" "cfg/cs2whitelist/core.cfg"

# KZ
install_cfg "CS2/cs2kz-server-config.txt" "cfg/cs2kz-server-config.txt"
install_cfg "CS2/multiaddonmanager/multiaddonmanager.cfg" "cfg/multiaddonmanager/multiaddonmanager.cfg"

# Misc
install_cfg "CS2/AcceleratorCS2/config.json" "addons/AcceleratorCS2/config.json"
install_cfg "CS2/cleanercs2/config.cfg" "addons/cleanercs2/config.cfg"

# Fill in secrets in configs

cfg="$server_dir/game/csgo/cfg/cs2admin/core.cfg"
modify_config "$cfg" "ServerID" "$SB_SERVER_ID"
modify_config "$cfg" "WebhookUrl" "$DC_ADMIN_WEBHOOK"
modify_config "$cfg" "host" "$DB_HOST"
modify_config "$cfg" "port" "$DB_PORT"
modify_config "$cfg" "user" "$DB_USER"
modify_config "$cfg" "pass" "$DB_PASS"
modify_config "$cfg" "database" "$SB_DB_NAME"

cfg="$server_dir/game/csgo/cfg/fkz-api/core.cfg"
modify_config "$cfg" "api_key" "$FKZ_APIKEY"
modify_config "$cfg" "server_ip" "$IP"
modify_config "$cfg" "server_port" "$PORT"
modify_config "$cfg" "db_host" "$DB_HOST"
modify_config "$cfg" "db_port" "$DB_PORT"
modify_config "$cfg" "db_user" "$DB_USER"
modify_config "$cfg" "db_pass" "$DB_PASS"
modify_config "$cfg" "db_database" "$GL_DB_NAME"

cfg="$server_dir/game/csgo/cfg/cs2menus/core.cfg"
modify_config "$cfg" "Host" "$DB_HOST"
modify_config "$cfg" "Port" "$DB_PORT"
modify_config "$cfg" "User" "$DB_USER"
modify_config "$cfg" "Pass" "$DB_PASS"
modify_config "$cfg" "Name" "$GL_DB_NAME"

cfg="$server_dir/game/csgo/cfg/cs2kz-server-config.txt"
modify_config "$cfg" "host" "$DB_HOST"
modify_config "$cfg" "port" "$DB_PORT"
modify_config "$cfg" "user" "$DB_USER"
modify_config "$cfg" "pass" "$DB_PASS"
modify_config "$cfg" "database" "$GL_DB_NAME"
modify_config "$cfg" "apiKey" "$CS2KZ_APIKEY"

cfg="$server_dir/game/csgo/cfg/cs2rtv/core.cfg"
modify_config "$cfg" "SteamApiKey" "$WS_APIKEY"

cfg="$server_dir/game/csgo/cfg/cs2whitelist/core.cfg"
modify_config "$cfg" "ApiKey" "$WS_APIKEY"

# Mount configs that plugins write to at runtime, so they persist
install_mount "configs/admins_simple.ini" "cfg/cs2admin/admins_simple.ini"
install_mount "configs/admins.cfg" "cfg/cs2admin/admins.cfg"
install_mount "configs/admin_overrides.cfg" "cfg/cs2admin/admin_overrides.cfg"
install_mount "configs/admin_groups.cfg" "cfg/cs2admin/admin_groups.cfg"
install_mount "configs/tags.cfg" "cfg/cs2admin/tags.cfg"
install_mount "configs/whitelist" "cfg/cs2whitelist"

# Mount logs
install_mount "$ID/logs" "logs"
install_mount "$ID/logs/kz" "addons/cs2kz/logs"
install_mount "$ID/dumps" "addons/AcceleratorCS2/dumps"
install_mount "$ID/queue.txt" "addons/cs2admin/queue.txt"

# Mount replays
install_mount "kzreplays" "kzreplays"

# Mount workshop
rm -rf "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"
ln -s "/mounts/$ID/workshop" "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"

# Write WebAPI key
rm -rf "$server_dir/game/csgo/webapi_authkey.txt"
echo "$WS_APIKEY" > "$server_dir/game/csgo/webapi_authkey.txt"

# Run the server.
"$server_dir/game/cs2.sh" -dedicated -disable_workshop_command_filtering -ip "$IP" -port "$PORT" -authkey "$WS_APIKEY" +sv_setsteamaccount "$GSLT" +map "$MAP" +host_workshop_map "$WS_MAP" +exec server.cfg -maxplayers 64 -nohltv
