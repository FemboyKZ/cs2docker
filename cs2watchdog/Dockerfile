FROM debian:bookworm-slim

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        lib32stdc++6 ca-certificates curl jq tar \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY cs2watchdog.sh .
RUN chmod 555 cs2watchdog.sh

ENTRYPOINT ["/app/cs2watchdog.sh"]
