FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        jq \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY cs2server.sh /app/cs2server.sh
COPY run.sh /user/run.sh
RUN chmod 555 /app/cs2server.sh /user/run.sh

ENTRYPOINT ["/app/cs2server.sh"]
