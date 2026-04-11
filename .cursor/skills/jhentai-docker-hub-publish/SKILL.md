---
name: jhentai-docker-hub-publish
description: >-
  Every Hub push MUST be multi-arch linux/amd64 + linux/arm64 for hemumoe/jhentai,
  with both the computed x.y.z-hhh tag and latest. Builds with docker buildx
  (docker-container driver on Windows/macOS when needed). Use when the user asks
  to publish or push the Docker image to Docker Hub, sync the registry, or
  refresh Hub after code changes — never push a single-arch image to these tags.
---

# JHenTai Docker Hub — local build and push

## When this applies

This workflow is for the **JHenTai-Docker** fork: Dockerfile at repo root, image **`hemumoe/jhentai`**.

**Hard requirements for every push:**

1. **Architectures:** **`linux/amd64` and `linux/arm64` together** in one manifest list. Do **not** push only `linux/amd64` (or only `linux/arm64`) to **`hemumoe/jhentai`** — that overwrites the tag with a single-arch manifest and breaks users on the other architecture.
2. **Tags:** **`x.y.z-hhh`** (computed below) **and** **`latest`**, same manifest list for both.

## Prerequisites

- **Docker Desktop** running (Linux engine), **`docker buildx`** available.
- Host logged in to Docker Hub with push rights: `docker login` (account that may push `hemumoe/jhentai`).
- Shell: on Windows use **PowerShell**; chain commands with **`;`**, not `&&`.

## Step 1 — Builder that can build both architectures

The default **`docker`** buildx driver often only runs **`linux/amd64`** on the host. **`--platform linux/amd64,linux/arm64`** then fails with **`exec format error`** on x86 Windows/macOS.

**Before every multi-arch push**, ensure the active builder is **`docker-container`** (BuildKit + QEMU). Create once per machine if missing:

```bash
docker buildx create --name jhentai-multi --driver docker-container --bootstrap --use
```

If **`jhentai-multi`** already exists: **`docker buildx use jhentai-multi`**.

Confirm: **`docker buildx inspect`** shows the builder in use. Optional after push, switch back for local compose: **`docker buildx use desktop-linux`** (name from **`docker buildx ls`**).

## Step 2 — Compute the image tag

1. Read **`pubspec.yaml`**: first line matching `^version:` → value like `8.0.12+309`. Let **`x.y.z`** = part before **`+`**.
2. Fork revision (decimal **0–4095**):
   - If **`docker/fork_revision`** exists: first line, strip whitespace.
   - Else: digits after **`+`** in `pubspec` `version:`; if missing, use `0`.
3. Validate integer **0–4095**. Convert with 10#-safe arithmetic, then **`hhh`** = `printf '%03x' "$DEC"` (lowercase hex).
4. **Tag** = `x.y.z-hhh` (example: fork file `310` on `8.0.12` → **`8.0.12-136`**).

Same logic as `.github/workflows/docker-publish.yml` (`Image tag` step).

## Step 3 — Build and push (always both platforms, both tags)

Run from **repository root**. Replace **`TAG`** with the computed tag.

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t hemumoe/jhentai:TAG \
  -t hemumoe/jhentai:latest \
  --push .
```

Single line (e.g. PowerShell):

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t hemumoe/jhentai:TAG -t hemumoe/jhentai:latest --push .
```

First build can take a long time; cached rebuilds are faster.

## After push

Verify **both** tags expose **two** architectures:

```bash
docker manifest inspect hemumoe/jhentai:TAG
docker manifest inspect hemumoe/jhentai:latest
```

Expect **`linux/amd64`** and **`linux/arm64`** under `manifests` for each.

## Bump for a new release

- Change app line in **`pubspec.yaml`** if needed.
- Increment **`docker/fork_revision`** (or `+` build if file absent) so **`hhh`** changes and the version tag is new.
- After push, **`latest`** on Hub matches that multi-arch build.

## Optional: remove legacy Hub tags

See **`scripts/dockerhub-delete-tags.sh`** and **`DOCKER.md`** / **`DOCKER_cn.md`**. **Do not** treat **`latest`** as legacy if you maintain it via this skill.

## If push fails

- **`denied` / `unauthorized`:** **`docker login`** with a user that can push **`hemumoe/jhentai`**.
- **`exec format error`:** use **`docker-container`** builder (Step 1); do **not** “fix” by pushing **`--platform linux/amd64`** only.
- **Transient `apt-get` / mirror errors:** retry the same **`linux/amd64,linux/arm64`** build; do not downgrade to single-arch.
- Manifest missing an arch: ensure **`--platform linux/amd64,linux/arm64`** and inspect output above.
