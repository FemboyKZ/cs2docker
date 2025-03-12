# CS2 Docker

Deduplicated Counter-Strike 2 server hosting in Docker.

## Watchdog

The watchdog image keeps Counter-Strike 2 up to date.

#### Volumes:

- `/watchdog` - The directory where Steam and Counter-Strike 2 will be installed to.

## Server

The server image runs an instance of a Counter-Strike 2 server. You can run as many as your hardware can handle.

#### Volumes:

- `/watchdog` - Has to be the same as the one passed to the watchdog.
- `/user/run.sh` - The script that sets up and runs the server.

#### Volumes convention (not used by cs2docker itself, but it's the recommended calling convention):
- `/layers` - Plugin binaries that you copy-paste from `run.sh` (CounterStrikeSharp, RockTheVote, etc.).
- `/mounts` - Files and directories that you symlink from `run.sh` (maplist.txt, log directories, etc.).

## run.&#8203;sh

It's recommended you edit [the example in this README](#runsh-1).

#### Environment variables:

- `$build_ver` - The version number of Counter-Strike 2 that the server should use. 
- `$build_dir` - The directory where that version of Counter-Strike 2 is installed. 
- `$server_dir` - The directory where you should build the server. 
- Everything passed to Docker.

## Auto restart on update

Counter-Strike 2 has no built-in `-autoupdate` functionality to automatically restart the server when a new update is detected.
You need to install my [AutoRestart](https://github.com/Szwagi/cs2docker-autorestart/) plugin for servers to restart on update without manual intervention.

## Binding IP and port

Counter-Strike 2's built in `ip` and `port` launch options are broken. Use Docker IP/port binding instead.

```yml
ports:
  - "172.16.16.16:27020:27015:/udp"
  - "172.16.16.16:27020:27015:/tcp"
```

## Example

#### docker-compose.yml

```yml
services:
  cs2watchdog:
    image: cs2watchdog
    container_name: cs2watchdog
    restart: unless-stopped
    user: 1000:1000
    volumes:
      - ./watchdog:/watchdog
  cs2server1:
    image: cs2server
    container_name: cs2server1
    restart: unless-stopped
    user: 1000:1000
    ports:
      - "27015:27015/udp"
      - "27015:27015/tcp"
    environment:
      - GSLT=
    volumes:
      - ./watchdog:/watchdog
      - ./layers:/layers
      - ./mounts:/mounts
      - ./run.sh:/user/run.sh
  cs2server2:
    image: cs2server
    container_name: cs2server2
    restart: unless-stopped
    user: 1000:1000
    ports:
      - "27020:27015/udp"
      - "27020:27015/tcp"
    environment:
      - GSLT=
    volumes:
      - ./watchdog:/watchdog
      - ./layers:/layers
      - ./mounts:/mounts
      - ./run.sh:/user/run.sh
```

#### run.&#8203;sh

```bash
#!/bin/bash

set -ueEo pipefail

echo "Build version: $build_ver"
echo "Build directory: $build_dir"
echo "GSLT: $GSLT"

# Symlink all the server files.
cp -rs "$build_dir"/* "$server_dir"

# The binary can't be symlinked because it checks it's own location and sets CWD based on that.
rm "$server_dir/game/bin/linuxsteamrt64/cs2"
cp "$build_dir/game/bin/linuxsteamrt64/cs2" "$server_dir/game/bin/linuxsteamrt64/cs2"

# Install MetaMod.
tar -xf "/layers/metamod.tar.gz" -C "$server_dir/game/csgo"
sed -i '0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/' "$server_dir/game/csgo/gameinfo.gi"

# Install CS2KZ.
tar -xf "/layers/cs2kz.tar.gz" -C "$server_dir/game/csgo"

# Mount workshop folder.
mkdir -p "$server_dir/game/bin/linuxsteamrt64/steamapps"
ln -s "/mounts/workshop" "$server_dir/game/bin/linuxsteamrt64/steamapps/workshop"

# Run the server
"$server_dir/game/bin/linuxsteamrt64/cs2" -dedicated -usercon +sv_setsteamaccount "$GSLT" +map de_dust2 +host_workshop_map 3070194623
```
