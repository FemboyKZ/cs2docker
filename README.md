# CS2 Docker

Work in progress.

```yml
services:
  cs2watchdog:
    image: cs2watchdog
    container_name: cs2watchdog
    user: 1000:1000
    volumes:
      - /tmp/repo:/repo
  cs2server:
    image: cs2server
    container_name: cs2server
    network_mode: host
    user: 1000:1000
    volumes:
      - /tmp/repo:/repo
```
