FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest-container-runtime-depot

RUN printf '%s\n' \
    'Acquire::Check-Valid-Until "false";' \
    'Acquire::AllowReleaseInfoChange::Suite "true";' \
    'Acquire::AllowReleaseInfoChange::Version "true";' \
    > /etc/apt/apt.conf.d/99-ci-ignore-expired-release

RUN for list in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do \
    [ -f "$list" ] || continue; \
    sed -i 's@deb\.debian\.org/debian-security@archive.debian.org/debian-security@' "$list"; \
done

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends --no-install-suggests \
        jq sqlite3 \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY cs2server.sh /app/cs2server.sh
COPY run.sh /user/run.sh
RUN chmod 555 /app/cs2server.sh /user/run.sh

ENTRYPOINT ["/app/cs2server.sh"]
