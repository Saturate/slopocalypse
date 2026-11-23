# Dedicated server image.
#   docker build -t slopocalypse-server .
#   docker run -d --name slopocalypse -p 7777:7777/udp -v slopocalypse-data:/data slopocalypse-server
# The build stage exports the Linux game inside the container (Rust libraries included), so the
# image builds the same from Windows, macOS or Linux. Needs the LFS textures checked out.
# To package an export made elsewhere instead (the release workflow does):
#   docker build --build-arg EXPORT=prebuilt --build-context linux-export=<unzipped linux build> .
ARG EXPORT=build

# The admin web app (web/) built on its own: the export stage only needs its files.
FROM node:24.11.1-bookworm-slim AS web
WORKDIR /src
COPY package.json package-lock.json ./
COPY web/package.json web/
RUN npm ci --workspace web --include-workspace-root=false
COPY web/ web/
COPY modules/web/api/ modules/web/api/
RUN npm run build -w web

FROM rust:1.95.0-bookworm AS build
COPY --from=node:24.11.1-bookworm-slim /usr/local/bin/node /usr/local/bin/node
RUN apt-get update && apt-get install -y --no-install-recommends unzip zip && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Godot and the addons in their own layer, rebuilt only when the tools change.
COPY tools/ tools/
RUN node tools/get-godot.ts && node tools/get-addons.ts
COPY . .
COPY --from=web /src/modules/web/static/ modules/web/static/
# The 1 GB export templates and the Rust build are cached between image builds.
RUN --mount=type=cache,target=/src/tools/godot/editor_data/export_templates \
    --mount=type=cache,target=/src/target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    node tools/export.ts --os linux

# The Linux player zip, for tools/release.ts: docker build --target linux-zip --output type=local,dest=DIR .
FROM scratch AS linux-zip
COPY --from=build /src/build/slopocalypse-linux.zip /

FROM scratch AS prebuilt
COPY --from=linux-export / /src/build/linux

FROM ${EXPORT} AS export

FROM debian:bookworm-slim
ARG VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/Saturate/slopocalypse" \
      org.opencontainers.image.title="Slopocalypse server" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}"
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /data --shell /usr/sbin/nologin slopocalypse
COPY --from=export /src/build/linux /opt/slopocalypse
RUN chmod +x /opt/slopocalypse/Slopocalypse.x86_64
# user:// (logs, journals) resolves under HOME, so everything the server writes lands in /data.
ENV HOME=/data
VOLUME /data
USER slopocalypse
WORKDIR /opt/slopocalypse
EXPOSE 7777/udp
# Tuning without a rebuild: mount files over /opt/slopocalypse/tweaks/<res path>, see TWEAKING.md.
# The web page (TCP): -e WEB_PORT=8080 moves it off the game's port, -e WEB_PASSWORD=... turns on
# the admin pages; behind an HTTPS proxy publish it on loopback only (-p 127.0.0.1:8080:8080/tcp).
ENTRYPOINT ["./Slopocalypse.x86_64", "--headless", "--"]
CMD ["--server=7777", "--save=/data/world.db", "--web"]
