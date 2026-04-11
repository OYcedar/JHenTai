---
name: jhentai-docker-hub-publish
description: >-
  Builds multi-arch (linux/amd64, linux/arm64) JHenTai Docker images and pushes
  them to Docker Hub as hemumoe/jhentai with the computed x.y.z-hhh tag and
  latest simultaneously. Use when the user asks to update or publish the Docker
  image locally, push to Docker Hub after changes, refresh the container
  registry, or sync Hub with the repo.
---

# JHenTai Docker Hub — local build and push

## When this applies

This workflow is for the **JHenTai-Docker** fork: Dockerfile at repo root, image **`hemumoe/jhentai`**. Each push must publish **two tags** for the same manifest:

1. **Version tag** **`x.y.z-hhh`** (computed below; stable pin for compose/README).
2. **`latest`** (always points at the same multi-arch image as that release).

## Prerequisites

- **Docker Desktop** running (Linux engine), **`docker buildx`** available.
- Host logged in to Docker Hub with push rights: `docker login` (account that may push `hemumoe/jhentai`).
- Shell: on Windows use **PowerShell**; chain commands with **`;`**, not `&&`.

## Multi-arch on Docker Desktop (Windows / macOS)

The default **`docker`** buildx driver often only runs **`linux/amd64`** on the host. Building **`linux/arm64`** with `--platform linux/amd64,linux/arm64` then fails with **`exec format error`** on non-ARM machines.

**Fix:** use a **`docker-container`** builder (BuildKit in a container with QEMU). Create once per machine, then select it before `buildx build`:

```bash
docker buildx create --name jhentai-multi --driver docker-container --bootstrap --use
```

From the repo root, run the **`docker buildx build ... --push`** commands below (they apply to the active builder).

When finished, you can switch back for local **`docker compose`** (optional):

```bash
docker buildx use desktop-linux
```

(The exact default name may be **`default`** or **`desktop-linux`** — run **`docker buildx ls`**.)

## Compute the image tag

1. Read **`pubspec.yaml`**: first line matching `^version:` → value like `8.0.12+309`. Let **`x.y.z`** = part before **`+`**.
2. Fork revision (decimal **0–4095**):
   - If **`docker/fork_revision`** exists: first line, strip whitespace.
   - Else: digits after **`+`** in `pubspec` `version:`; if missing, use `0`.
3. Validate integer **0–4095**. Convert with 10#-safe arithmetic, then **`hhh`** = `printf '%03x' "$DEC"` (lowercase hex).
4. **Tag** = `x.y.z-hhh` (example: fork file `310` on `8.0.12` → **`8.0.12-136`**).

Match the same logic as `.github/workflows/docker-publish.yml` (`Image tag` step), when the workflow is configured to use the same tagging scheme.

## Commands (run from repository root)

Replace `TAG` with the computed tag (e.g. `8.0.12-136`). **Always pass both `-t` flags** so Hub gets the version pin and **`latest`** in one build.

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t hemumoe/jhentai:TAG \
  -t hemumoe/jhentai:latest \
  --push .
```

Single line (e.g. PowerShell copy-paste):

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t hemumoe/jhentai:TAG -t hemumoe/jhentai:latest --push .
```

PowerShell: `Set-Location` to the repo root, then the same `docker buildx build` line (substitute the computed `TAG`).

First build can take a long time; cached rebuilds are faster.

## After push

Verify multi-arch manifest for **both** tags (same digest/manifest list):

```bash
docker manifest inspect hemumoe/jhentai:TAG
docker manifest inspect hemumoe/jhentai:latest
```

Expect **`linux/amd64`** and **`linux/arm64`** under `manifests` for each.

## Bump for a new release

- Change app line in **`pubspec.yaml`** if needed.
- Increment **`docker/fork_revision`** (or `+` build if file absent) so **`hhh`** changes and the version tag is new.
- After push, **`latest`** on Hub matches that build.

## Optional: remove legacy Hub tags

See **`scripts/dockerhub-delete-tags.sh`** and **`DOCKER.md`** / **`DOCKER_cn.md`** for cleaning up obsolete tag names (e.g. old `*-web` aliases). **Do not** treat `latest` as legacy if you are actively maintaining it via this skill.

## If push fails

- `denied` / `unauthorized`: run **`docker login`** with a user that can push **`hemumoe/jhentai`**.
- `no matching manifest for linux/amd64`: ensure **`--platform linux/amd64,linux/arm64`** (multi-arch index).
