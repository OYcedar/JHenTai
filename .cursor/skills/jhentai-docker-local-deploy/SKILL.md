---
name: jhentai-docker-local-deploy
description: >-
  Rebuilds and runs the JHenTai-Docker stack locally via docker compose after
  code changes. Use when the user asks to deploy locally with Docker, verify the
  image after edits, run compose up --build, refresh the jhentai container, or
  wants the agent to automatically deploy to local Docker when implementation
  is finished in this repository.
---

# JHenTai — local Docker deploy (compose)

## When to run

- **After** finishing code changes in **JHenTai-Docker** (same repo as root `Dockerfile` and [`docker-compose.yml`](docker-compose.yml)).
- When the user explicitly asks for local Docker / compose deploy, or says to auto-deploy locally after edits.

**Skip** if the user only wanted a plan, docs-only change, or said not to run Docker.

## Prerequisites

- **Docker** available (`docker compose` v2 or `docker-compose`).
- Shell on Windows: **PowerShell**; chain with **`;`**, not `&&`.

## Commands (repository root)

`Set-Location` to the repo root (directory containing `docker-compose.yml`), then:

```powershell
docker compose build --no-cache; docker compose up -d
```

For faster iteration when only app code changed and Dockerfile layers cache well:

```powershell
docker compose up -d --build
```

- Service / container name: **`jhentai`** (see compose file).
- Default URL: **`http://localhost:8080`** (map `8080:8080`).

## Verify

```powershell
docker compose ps
docker compose logs jhentai --tail 80
```

Optional: open `http://localhost:8080` or `curl` `/api/health` if the API exposes it.

## If build or start fails

- **Port in use**: change host port in `docker-compose.yml` or stop the conflicting process.
- **Build errors**: read the **docker build** step output; fix Dart/Flutter or server compile issues, then retry.
- **Permission / volume**: on Linux check `PUID`/`PGID`; on Windows Docker Desktop file sharing.

## Relation to other skills

- **Hub publish** (multi-arch push): use [jhentai-docker-hub-publish](../jhentai-docker-hub-publish/SKILL.md), not this skill.
- This skill is **local only** — no registry push.

## Agent checklist (post-implementation)

1. Confirm edits are saved and the user did not forbid running commands.
2. `Set-Location` to repo root.
3. Run `docker compose up -d --build` (or `build` then `up` as above).
4. Report exit codes; show last lines of `docker compose logs jhentai` if non-trivial.
