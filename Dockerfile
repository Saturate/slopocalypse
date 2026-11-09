# Dedicated server image.
#   docker build -t slopocalypse-server .
#   docker run -d --name slopocalypse -p 7777:7777/udp -v slopocalypse-data:/data slopocalypse-server
# The build stage exports the Linux game inside the container (Rust libraries included), so the
# image builds the same from Windows, macOS or Linux. Needs the LFS textures checked out.

FROM rust:1.95.0-bookworm AS build
COPY --from=node:24.11.1-bookworm-slim /usr/local/bin/node /usr/local/bin/node
RUN apt-get update && apt-get install -y --no-install-recommends unzip zip && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Godot and the addons in their own layer, rebuilt only when the tools change.
COPY tools/ tools/
RUN node tools/get-godot.ts && node tools/get-addons.ts
COPY . .
# The 1 GB export templates and the Rust build are cached between image builds.
RUN --mount=type=cache,target=/src/tools/godot/editor_data/export_templates \
    --mount=type=cache,target=/src/target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    node tools/export.ts --os linux

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /data --shell /usr/sbin/nologin slopocalypse
COPY --from=build /src/build/linux /opt/slopocalypse
# user:// (logs, journals) resolves under HOME, so everything the server writes lands in /data.
ENV HOME=/data
VOLUME /data
USER slopocalypse
WORKDIR /opt/slopocalypse
EXPOSE 7777/udp
# Tuning without a rebuild: mount files over /opt/slopocalypse/tweaks/<res path>, see TWEAKING.md.
ENTRYPOINT ["./Slopocalypse.x86_64", "--headless", "--"]
CMD ["--server=7777", "--save=/data/world.db"]
