#!/bin/bash

set -ueEo pipefail

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Run the server.
"$server_dir/game/bin/linuxsteamrt64/cs2" -dedicated -usercon +sv_setsteamaccount "$GSLT" +map de_dust2
