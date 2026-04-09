# Stage 1: Build Flutter Web frontend
FROM ghcr.io/cirruslabs/flutter:stable AS web-build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY lib/ lib/
COPY web/ web/
COPY assets/ assets/

RUN flutter config --no-analytics && \
    flutter pub get

RUN flutter build web \
    --release \
    --target lib/src/main_web.dart \
    --web-renderer html

# Stage 2: Build Dart backend server (AOT compiled)
FROM dart:stable AS server-build

WORKDIR /app/server
COPY server/pubspec.yaml server/pubspec.lock* ./
RUN dart pub get

COPY server/ .
RUN dart compile exe bin/server.dart -o bin/server

# Stage 3: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 jhentai && \
    useradd -u 1000 -g jhentai -m -s /bin/bash jhentai

COPY --from=server-build /app/server/bin/server /app/server
COPY --from=web-build /app/build/web /app/web

COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

RUN mkdir -p /data && chown jhentai:jhentai /data

ENV JH_DATA_DIR=/data
ENV JH_PORT=8080
ENV JH_HOST=0.0.0.0
ENV JH_WEB_DIR=/app/web
ENV PUID=1000
ENV PGID=1000

EXPOSE 8080

VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/api/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
