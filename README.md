# CS2 Docker

Work in progress.

```yml
services:
  cs2watchdog:
    image: cs2watchdog
    container_name: cs2watchdog
    user: 1000:1000
    volumes:
      - /opt/repo:/repo # The user needs write permissions
```
