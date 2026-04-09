#!/bin/bash
set -e

PUID=${PUID:-1000}
PGID=${PGID:-1000}

if [ "$(id -u)" = "0" ]; then
  groupmod -o -g "$PGID" jhentai 2>/dev/null || true
  usermod -o -u "$PUID" jhentai 2>/dev/null || true
  chown -R jhentai:jhentai /data

  exec runuser -u jhentai -- /app/server "$@"
else
  exec /app/server "$@"
fi
