---
name: jhentai-docker-hub-publish
description: >-
  Builds multi-arch (linux/amd64, linux/arm64) JHenTai Docker images and pushes
  them to Docker Hub as hemumoe/jhentai with tag x.y.z-hhh. Use when the user
  asks to update or publish the Docker image locally, push to Docker Hub after
  changes, refresh the container registry, or sync Hub with the repo.
---

# JHenTai Docker Hub — local build and push

## When this applies

This workflow is for the **JHenTai-Docker** fork: Dockerfile at repo root, image **`hemumoe/jhentai`**, tags **`x.y.z-hhh`** only (no `latest`).

## Prerequisites

- **Docker Desktop** running (Linux engine), **`docker buildx`** available.
- Host logged in to Docker Hub with push rights: `docker login` (account that may push `hemumoe/jhentai`).
- Shell: on Windows use **PowerShell**; chain commands with **`;`**, not `&&`.

## Compute the image tag

1. Read **`pubspec.yaml`**: first line matching `^version:` → value like `8.0.12+309`. Let **`x.y.z`** = part before **`+`**.
2. Fork revision (decimal **0–4095**):
   - If **`docker/fork_revision`** exists: first line, strip whitespace.
   - Else: digits after **`+`** in `pubspec` `version:`; if missing, use `0`.
3. Validate integer **0–4095**. Convert with 10#-safe arithmetic, then **`hhh`** = `printf '%03x' "$DEC"` (lowercase hex).
4. **Tag** = `x.y.z-hhh` (example: fork file `310` on `8.0.12` → **`8.0.12-136`**).

Match the same logic as `.github/workflows/docker-publish.yml` (`Image tag` step).

## Commands (run from repository root)

Replace `TAG` with the computed tag (e.g. `8.0.12-136`).

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t hemumoe/jhentai:TAG --push .
```

PowerShell: `Set-Location` to the repo root, then the same `docker buildx build` line (use the computed `TAG`, not a hardcoded path).

First build can take a long time; cached rebuilds are faster.

## After push

Verify multi-arch manifest:

```bash
docker manifest inspect hemumoe/jhentai:TAG
```

Expect **`linux/amd64`** and **`linux/arm64`** under `manifests`.

## Bump for a new release

- Change app line in **`pubspec.yaml`** if needed.
- Increment **`docker/fork_revision`** (or `+` build if file absent) so **`hhh`** changes and the tag is new.

## Optional: remove legacy Hub tags

See **`scripts/dockerhub-delete-tags.sh`** and **`DOCKER.md`** / **`DOCKER_cn.md`** (old names like `latest`, bare semver, `*-web`).

## If push fails

- `denied` / `unauthorized`: run **`docker login`** with a user that can push **`hemumoe/jhentai`**.
- `no matching manifest for linux/amd64`: ensure **`--platform linux/amd64,linux/arm64`** (multi-arch index).
