FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        jq \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /user
COPY run.sh .
RUN chmod 555 run.sh

WORKDIR /app
COPY cs2server.sh .
RUN chmod 555 cs2server.sh

ENTRYPOINT ["/app/cs2server.sh"]
