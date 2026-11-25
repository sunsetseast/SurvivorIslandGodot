FROM node:24-bookworm-slim AS bake
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --silent --show-error \
    https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o /tmp/godot.zip \
    && echo 'cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4  /tmp/godot.zip' | sha256sum -c - \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot
WORKDIR /src
COPY . .
RUN GODOT_BIN=/usr/local/bin/godot bash ci/build-server.sh \
    && find build/server/.godot -mindepth 1 ! -name global_script_class_cache.cfg -delete

FROM caddy:2.10.2 AS gateway

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* && useradd --system --create-home survivor
COPY --from=bake /usr/local/bin/godot /usr/local/bin/godot
COPY --from=bake /src/build/server /opt/survivor
COPY --from=gateway /usr/bin/caddy /usr/local/bin/caddy
COPY server/Caddyfile server/entrypoint.sh /opt/
WORKDIR /opt/survivor
USER survivor
ENV PORT=8080 SURVIVOR_WS_PORT=8061
ENTRYPOINT ["bash", "/opt/entrypoint.sh"]
