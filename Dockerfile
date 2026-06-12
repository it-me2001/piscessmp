FROM eclipse-temurin:21-jre-jammy

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    netcat-openbsd \
    python3 \
    unzip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /piscessmp

COPY scripts ./scripts
COPY server/config-templates ./server/config-templates
COPY server/assets ./server/assets
COPY server/server-icon.png ./docker/server-icon.png
COPY deploy/backup.env.example ./deploy/backup.env.example
COPY docker/entrypoint.sh ./docker/entrypoint.sh
COPY setup.sh ./setup.sh

RUN chmod +x setup.sh scripts/*.sh docker/entrypoint.sh scripts/update-lib.py \
  && mkdir -p server/plugins server/logs server/backups deploy

ENV ACCEPT_EULA=false \
    MEMORY_MIN=2G \
    MEMORY_MAX=4G \
    UPDATE_ON_START=false

EXPOSE 25565/tcp 25575/tcp 19132/udp 24454/udp 8100/tcp 8080/tcp

VOLUME ["/piscessmp/server/world", "/piscessmp/server/spawn", "/piscessmp/server/plugins", "/piscessmp/server/logs", "/piscessmp/server/backups"]

ENTRYPOINT ["/piscessmp/docker/entrypoint.sh"]
