#!/bin/bash
set -e

PUID=${PUID:-1000}
PGID=${PGID:-1000}

if [ "$(id -u)" = "0" ]; then
  groupmod -o -g "$PGID" jhentai 2>/dev/null || true
  usermod -o -u "$PUID" jhentai 2>/dev/null || true

  if [ ! -f /data/.ownership_set ] || \
     [ "$(stat -c %u /data)" != "$PUID" ] || \
     [ "$(stat -c %g /data)" != "$PGID" ]; then
    chown -R jhentai:jhentai /data
    touch /data/.ownership_set
  fi

  exec runuser -u jhentai -- /app/server "$@"
else
  exec /app/server "$@"
fi
