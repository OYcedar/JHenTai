# Stage 1: Build Flutter Web frontend (platform-independent output)
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:3.41.6 AS web-build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY web/ web/

RUN flutter config --no-analytics && \
    flutter pub get

COPY lib/ lib/
COPY assets/ assets/

RUN flutter build web \
    --release \
    --target lib/src/main_web.dart

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
    sqlite3 \
    ca-certificates \
    wget \
    gosu \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/lib/*/libsqlite3.so.0 /usr/lib/libsqlite3.so

RUN groupadd -g 1000 jhentai && \
    useradd -u 1000 -g jhentai -m -s /bin/bash jhentai

COPY --from=server-build /app/server/bin/server /app/server
COPY --from=web-build /app/build/web /app/web

COPY docker-entrypoint.sh /app/docker-entrypoint.sh
# Strip Windows CRLF so the script runs on Linux (avoids "no such file or directory" on exec).
RUN sed -i 's/\r$//' /app/docker-entrypoint.sh && chmod +x /app/docker-entrypoint.sh

RUN mkdir -p /data && chown jhentai:jhentai /data

ENV JH_DATA_DIR=/data
ENV JH_PORT=8080
ENV JH_HOST=0.0.0.0
ENV JH_WEB_DIR=/app/web
ENV PUID=1000
ENV PGID=1000

EXPOSE 8080

VOLUME ["/data"]

# Strip proxy env so healthcheck always hits local server (HTTP_PROXY breaks wget on some hosts).
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD /bin/sh -c 'env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy wget -q -O- --spider http://127.0.0.1:8080/api/health || exit 1'

ENTRYPOINT ["/bin/bash", "/app/docker-entrypoint.sh"]
