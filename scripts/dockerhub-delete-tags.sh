#!/usr/bin/env bash
# Delete tags on Docker Hub (e.g. legacy latest, bare semver, -web).
# Usage:
#   export DOCKERHUB_USERNAME=hemumoe
#   export DOCKERHUB_TOKEN=...   # Access Token from hub.docker.com → Account Settings → Security
#   ./scripts/dockerhub-delete-tags.sh latest 8.0.12 8.0 docker-web-48f728fb
set -euo pipefail
REPO="${DOCKERHUB_REPO:-hemumoe/jhentai}"
NS="${REPO%%/*}"
NAME="${REPO##*/}"
[ "$#" -ge 1 ] || { echo "usage: $0 <tag> [tag...]"; exit 1; }
[ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ] || {
  echo "Set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN"; exit 1
}
JSON=$(curl -sf -H "Content-Type: application/json" -X POST \
  -d "{\"username\": \"${DOCKERHUB_USERNAME}\", \"password\": \"${DOCKERHUB_TOKEN}\"}" \
  "https://hub.docker.com/v2/users/login/")
if command -v python3 >/dev/null 2>&1; then
  TOKEN=$(printf '%s' "$JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
else
  TOKEN=$(printf '%s' "$JSON" | sed -n 's/.*\"token\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p')
fi
[ -n "$TOKEN" ] || { echo "Docker Hub login failed"; exit 1; }
for tag in "$@"; do
  url="https://hub.docker.com/v2/repositories/${NS}/${NAME}/tags/${tag}/"
  code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT ${TOKEN}" "$url")
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    echo "Deleted: $tag"
  else
    echo "Skip or failed ($code): $tag"
  fi
done
