# JHenTai — Docker Deployment Guide

English | [简体中文](https://github.com/OYcedar/JHenTai/blob/master/DOCKER_cn.md) | [한국어](https://github.com/OYcedar/JHenTai/blob/master/DOCKER_kr.md)

---

## Table of Contents

- [Quick Start](#quick-start)
- [First Login](#first-login)
- [Configuration](#configuration)
- [Local Gallery Scanning](#local-gallery-scanning)
- [Backup](#backup)
- [Reverse Proxy](#reverse-proxy)
- [Docker Hub CI/CD](#docker-hub-cicd)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Pull from Docker Hub

Images are tagged **`x.y.z-hhh`** only:

- **`x.y.z`** — app semver from `pubspec.yaml` (`version:` before `+`).
- **`hhh`** — **three lowercase hex digits** (000–fff) for this Docker fork’s revision, decimal **0–4095** (see `docker/fork_revision`).

Example: `8.0.12+309` with fork revision `310` → **`8.0.12-136`** (`310` = `0x136`).

There is **no `latest`** tag; pin an explicit tag in compose or Unraid.

```bash
docker pull hemumoe/jhentai:8.0.12-136
```

**docker-compose.yml** (recommended):

```yaml
services:
  jhentai:
    image: hemumoe/jhentai:8.0.12-136
    container_name: jhentai
    ports:
      - "8080:8080"
    volumes:
      - jhentai-data:/data
    environment:
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
    mem_limit: 1g

volumes:
  jhentai-data:
```

```bash
docker-compose up -d
```

### Build from source

```bash
git clone https://github.com/OYcedar/JHenTai.git
cd JHenTai
docker-compose up -d --build
```

---

## First Login

Open `http://<your-server-ip>:8080` in a browser. On the first visit you will be asked for an **API token**. Find it in the container logs:

```bash
docker logs jhentai
```

Look for a line like:

```
Generated new API token: a3f9c2...
```

Enter this token in the browser setup page. It is saved to `localStorage` so you only need to do this once per browser.

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `JH_DATA_DIR` | `/data` | Data directory (database, logs, config, local gallery folder — **not** downloads if `JH_DOWNLOAD_DIR` is set) |
| `JH_DOWNLOAD_DIR` | `{JH_DATA_DIR}/download` | Root for gallery/archive files (`gallery/<gid>/`, `archive/<gid>/`). Set to a different path and mount it (e.g. Unraid `/mnt/user/media/comics/download` → `/downloads`) to keep comics off the appdata volume. |
| `JH_PORT` | `8080` | HTTP port |
| `JH_HOST` | `0.0.0.0` | Bind address |
| `JH_WEB_DIR` | `/app/web` | Web frontend static files directory |
| `JH_EXTRA_SCAN_PATHS` | *(empty)* | Comma-separated extra directories for local gallery scanning |
| `PUID` | `1000` | User ID for file ownership on mapped volumes |
| `PGID` | `1000` | Group ID for file ownership on mapped volumes |

### PUID / PGID (Unraid)

Set these to match your Unraid user so that downloaded files are owned by the correct user:

```yaml
environment:
  - PUID=99
  - PGID=100
```

---

### Separate download directory (Unraid / large libraries)

Keep SQLite and config on appdata, but put downloads on your media share:

```yaml
volumes:
  - /mnt/user/appdata/jhentai:/data
  - /mnt/user/media/comics/download:/downloads
environment:
  - JH_DOWNLOAD_DIR=/downloads
  - PUID=99
  - PGID=100
```

The server creates `gallery/` and `archive/` under that path.

---

## Local Gallery Scanning

Mount your media directories into the container and register them via `JH_EXTRA_SCAN_PATHS`:

```yaml
volumes:
  - /mnt/user/media/manga:/media/manga:ro
  - /mnt/user/media/doujinshi:/media/doujinshi:ro
environment:
  - JH_EXTRA_SCAN_PATHS=/media/manga,/media/doujinshi
```

The server scans these paths on startup and exposes them in the **Local Galleries** page of the web UI.

---

## Backup

By default everything under `/data` except that **`JH_DOWNLOAD_DIR`** can point elsewhere:

| Path | Contents |
|---|---|
| `/data/db.sqlite` | Database: settings, EH cookies, download task state |
| `{JH_DOWNLOAD_DIR}` (default `/data/download/`) | Downloaded gallery images and extracted archives |
| `/data/local_gallery/` | Galleries placed directly in the container |
| `/data/logs/` | Server logs (auto-rotated: max 10 files × 10 MB) |

**Full backup** (requires brief downtime):

```bash
docker-compose stop
docker run --rm -v jhentai-data:/data -v $(pwd)/backup:/backup alpine \
  tar czf /backup/jhentai-$(date +%Y%m%d).tar.gz -C / data
docker-compose start
```

**Database-only backup** (zero-downtime, SQLite online backup):

```bash
docker exec jhentai sqlite3 /data/db.sqlite ".backup /data/db_backup.sqlite"
```

---

## Reverse Proxy

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name jhentai.example.com;

    # Regular HTTP traffic
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket — required for real-time download progress
    location /ws/ {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       $host;
        proxy_read_timeout 86400s;
    }
}
```

### Caddy

```
jhentai.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Caddy handles WebSocket upgrades automatically.

### Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.jhentai.rule=Host(`jhentai.example.com`)"
  - "traefik.http.services.jhentai.loadbalancer.server.port=8080"
```

---

## Docker Hub CI/CD

The GitHub Actions workflow `.github/workflows/docker-publish.yml` automatically builds and pushes the image to Docker Hub whenever:

- A `v*` tag is pushed (versioned release, e.g. `v8.0.12`)
- A commit is pushed to `master` that touches server or web source files

**Required GitHub Secrets:**

| Secret | Value |
|---|---|
| `DOCKERHUB_TOKEN` | A Docker Hub **Access Token** (not your password) |

To create a Docker Hub token: Docker Hub → Account Settings → Security → New Access Token.

**Image tags published:**

| Tag | When |
|---|---|
| `x.y.z-hhh` | Every workflow run; `hhh` = hex of fork revision (file `docker/fork_revision`, or else `pubspec` `+` build number) |

**Fork revision:** Edit **`docker/fork_revision`** (one line, decimal **0–4095**) when you release this fork’s Docker image. If the file is missing, the number after **`+`** in `pubspec.yaml` `version:` is used instead.

**Removing old Hub tags** (`latest`, bare `8.0.12`, `8.0`, `*-web`, `docker-web-*`, etc.):

```bash
export DOCKERHUB_USERNAME=hemumoe
export DOCKERHUB_TOKEN=your_hub_access_token
chmod +x scripts/dockerhub-delete-tags.sh
./scripts/dockerhub-delete-tags.sh latest 8.0.12 8.0 8.0.12-web 8.0-web docker-web-48f728fb
```

Adjust the tag list to match what still exists on [Docker Hub](https://hub.docker.com/r/hemumoe/jhentai/tags). You can also delete tags in the Hub UI.

---

## Security

- All API endpoints except `/api/health` require `Authorization: Bearer <token>`
- The token is auto-generated on first launch and stored in the SQLite database
- The proxy endpoint is restricted to EH/EX domains only (SSRF protection)
- Local file endpoints are restricted to configured scan paths (path traversal protection)
- The web frontend stores the token in browser `localStorage`

---

## Troubleshooting

**Container won't start**  
→ Check logs: `docker logs jhentai`

**Unraid: crash loop (exit 255)**  
→ Do not use the `latest` tag (this fork publishes **`x.y.z-hhh` only**). Pull an explicit tag. If `/data` is on `/mnt/user/...`, in-container `chown` may fail; the entrypoint logs a **WARNING** and continues—ensure the host path is writable by your **`PUID`/`PGID`** (often `99:100` on Unraid). With `HTTP_PROXY`/`HTTPS_PROXY`, keep `127.0.0.1` and `localhost` in **`NO_PROXY`**.

**Permission denied writing to `/data`**  
→ Set `PUID`/`PGID` to match your host user, or run: `chown -R 1000:1000 /path/to/data-volume`

**WebSocket disconnects / downloads page shows no live updates**  
→ Ensure your reverse proxy passes `Upgrade`/`Connection` headers (see Nginx example above)

**Downloads interrupted after restart**  
→ Active downloads are automatically resumed when the server starts

**ExHentai content not loading**  
→ Go to **Settings → Site** and switch to **ExHentai**, then log in with valid ExHentai cookies
