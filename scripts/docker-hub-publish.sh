#!/usr/bin/env bash
# Build and push the JHenTai Docker image to Docker Hub with tag x.y.z-hhh (no GitHub Actions).
# Prerequisites: docker login
# Env: DOCKERHUB_USERNAME (default hemumoe), optional DOCKER_BUILDKIT=1
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

HHH=$(printf '%03x' "$FR")
USER="${DOCKERHUB_USERNAME:-hemumoe}"
IMAGE="${USER}/jhentai"
TAG="${SEMVER}-${HHH}"

echo "Image: ${IMAGE}:${TAG} (fork_revision=$FR -> 0x$HHH)"
docker build -t "${IMAGE}:${TAG}" .
docker tag "${IMAGE}:${TAG}" "${IMAGE}:latest"
docker push "${IMAGE}:${TAG}"
docker push "${IMAGE}:latest"
echo "Pushed ${IMAGE}:${TAG} and ${IMAGE}:latest"
