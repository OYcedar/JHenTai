#!/usr/bin/env bash
set -euo pipefail

PUID=${PUID:-1000}
PGID=${PGID:-1000}

# Dart / wget respect proxy env; always bypass proxy for loopback (NO_PROXY CIDRs are not universal).
_append_no_proxy() {
  local extra="127.0.0.1,localhost,::1"
  if [ -n "${NO_PROXY:-}" ]; then
    export NO_PROXY="$NO_PROXY,$extra"
  else
    export NO_PROXY="$extra"
  fi
  export no_proxy="$NO_PROXY"
}
_append_no_proxy

if [ "$(id -u)" = "0" ]; then
  groupmod -o -g "$PGID" jhentai 2>/dev/null || true
  usermod -o -u "$PUID" jhentai 2>/dev/null || true

  # Unraid /mnt/user and some NFS mounts: root in container cannot chown → would exit the whole script with set -e.
  if [ ! -f /data/.ownership_set ] || \
     [ "$(stat -c %u /data)" != "$PUID" ] || \
     [ "$(stat -c %g /data)" != "$PGID" ]; then
    set +e
    chown_err=$(chown -R jhentai:jhentai /data 2>&1)
    chown_rc=$?
    set -e
    if [ "$chown_rc" -eq 0 ]; then
      touch /data/.ownership_set 2>/dev/null || true
    else
      echo "WARNING: chown -R jhentai:jhentai /data failed (exit $chown_rc). This is common on Unraid user shares / FUSE." >&2
      echo "WARNING: If the server fails to write /data, fix host permissions (e.g. path owned by 99:100) or use a disk path instead of /mnt/user." >&2
      [ -n "$chown_err" ] && echo "$chown_err" | sed 's/^/  chown: /' >&2
    fi
  fi

  exec /usr/sbin/gosu jhentai /app/server "$@"
else
  exec /app/server "$@"
fi
