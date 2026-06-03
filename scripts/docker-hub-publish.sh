#!/usr/bin/env bash
# Build and push the JHenTai Docker image to Docker Hub with tag x.y.z-hhh (no GitHub Actions).
# Every publish bumps docker/fork_revision and refreshes README image tags first.
# Prerequisites: docker login
# Env:
#   DOCKERHUB_USERNAME (default hemumoe)
#   DOCKER_PLATFORMS (default linux/amd64,linux/arm64)
#   DOCKER_SKIP_VERSION_BUMP=1 to reuse the current docker/fork_revision.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER_LINE=$(grep -E '^version:' pubspec.yaml | head -1 | tr -d '[:space:]')
FULL="${VER_LINE#version:}"
SEMVER="${FULL%%+*}"
BUILD="${FULL#*+}"
BUILD="${BUILD:-0}"

if [[ -f docker/fork_revision ]]; then
  FR=$(tr -d ' \r\n\t' < docker/fork_revision)
else
  FR="$BUILD"
fi

if ! [[ "$FR" =~ ^[0-9]+$ ]] || (( FR < 0 || FR > 4095 )); then
  echo "error: docker/fork_revision must be a decimal 0–4095, got: $FR" >&2
  exit 1
fi

if [[ "${DOCKER_SKIP_VERSION_BUMP:-0}" != "1" ]]; then
  if (( FR >= 4095 )); then
    echo "error: docker/fork_revision is already 4095; cannot auto-increment" >&2
    exit 1
  fi
  FR=$((FR + 1))
  printf '%s\n' "$FR" > docker/fork_revision
fi

HHH=$(printf '%03x' "$FR")
USER="${DOCKERHUB_USERNAME:-hemumoe}"
IMAGE="${USER}/jhentai"
TAG="${SEMVER}-${HHH}"

DOC_IMAGE="hemumoe/jhentai"
DOC_TAG="${SEMVER}-${HHH}"
DOC_FILES=(
  README.md
  README_cn.md
  README_kr.md
  DOCKER.md
  DOCKER_cn.md
  DOCKER_kr.md
  docker-compose.yml
)
perl -0pi -e "s#\\Q${DOC_IMAGE}:\\E\\d+\\.\\d+\\.\\d+-[0-9a-f]{3}#${DOC_IMAGE}:${DOC_TAG}#g" "${DOC_FILES[@]}"

echo "Image: ${IMAGE}:${TAG} (fork_revision=$FR -> 0x$HHH)"
echo "Updated docs to ${DOC_IMAGE}:${DOC_TAG}"
PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64}"

echo "Platforms: ${PLATFORMS}"
docker buildx build \
  --platform "${PLATFORMS}" \
  --build-arg "JH_APP_VERSION=${FULL}" \
  --build-arg "JH_DOCKER_TAG=${TAG}" \
  --build-arg "JH_FORK_REVISION=${FR}" \
  -t "${IMAGE}:${TAG}" \
  -t "${IMAGE}:latest" \
  --push \
  .
echo "Pushed ${IMAGE}:${TAG} and ${IMAGE}:latest for ${PLATFORMS}"
