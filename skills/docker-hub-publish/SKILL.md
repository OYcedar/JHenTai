---
name: docker-hub-publish
description: >-
  Build and push this fork’s Docker image to Docker Hub using local scripts (tags
  x.y.z-hhh and latest). Do not rely on GitHub Actions for Docker Hub; use
  scripts/docker-hub-publish.sh or docker-hub-publish.ps1 after docker login.
---

# Docker Hub publish (this fork)

## Tag format

- **`x.y.z`**: from `pubspec.yaml` `version:` before `+`.
- **`hhh`**: three-digit lowercase hex of **`docker/fork_revision`** (decimal 0–4095). If the file is missing, use the build number after `+` in `pubspec.yaml` (same rule as [DOCKER.md](../../DOCKER.md)).
- **`latest`**: same image as the versioned tag above; always pushed together.

## Steps

1. Bump **`docker/fork_revision`** when releasing a new Hub image (optional bump `pubspec` semver if needed).
2. **`docker login`** to Docker Hub (account must have push access to the namespace, default **`hemumoe`**).
3. From repo root:
   - **Linux/macOS/Git Bash:** `chmod +x scripts/docker-hub-publish.sh && ./scripts/docker-hub-publish.sh`
   - **Windows PowerShell:** `powershell -ExecutionPolicy Bypass -File scripts/docker-hub-publish.ps1`
4. Override namespace: set **`DOCKERHUB_USERNAME`** (or edit script default).

## Notes

- There is **no** `docker-publish.yml` workflow in this fork; publishing is **manual** only.
- Flutter Web + Dart server multi-stage build matches [Dockerfile](../../Dockerfile); first run may take a long time.

## Cursor

The `.cursor/` directory is gitignored. To attach this skill in Cursor, copy this folder to `.cursor/skills/docker-hub-publish/` locally.
