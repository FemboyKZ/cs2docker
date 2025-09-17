FROM debian:bookworm-slim

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        lib32stdc++6 ca-certificates curl xmllint \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY fkzwldog.sh .
COPY manual.txt .
RUN chmod 555 fkzwldog.sh

ENTRYPOINT ["/app/fkzwldog.sh"]
