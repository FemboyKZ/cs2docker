#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"
echo "Restart time: $RESTART_TIME"
echo "Build dir: $build_dir"
echo "Server dir: $server_dir"

export daily_restart_time="$RESTART_TIME"
export discord_webhook="$DC_RESTART_WEBHOOK"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"


# Make sure necessary directories exist
mkdir -p "$server_dir/game/csgo/addons" "$server_dir/game/csgo/tmp"


# Run the server.
"$server_dir/game/cs2.sh" -dedicated -ip "$IP" -port "$PORT" -authkey "$WS_APIKEY" +sv_setsteamaccount "$GSLT" +map "$MAP" +mapgroup mg_custom +host_workshop_map "$WS_MAP" +exec server.cfg +game_type 3 +game_mode 0 -maxplayers 64 -nohltv
