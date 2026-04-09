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

```bash
docker pull hemumoe/jhentai:latest
```

**docker-compose.yml** (recommended):

```yaml
services:
  jhentai:
    image: hemumoe/jhentai:latest
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
| `JH_DATA_DIR` | `/data` | Data directory (database, downloads, logs) |
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

Everything is stored under the `/data` volume:

| Path | Contents |
|---|---|
| `/data/db.sqlite` | Database: settings, EH cookies, download task state |
| `/data/download/` | Downloaded gallery images and extracted archives |
| `/data/local_gallery/` | Galleries placed directly in the container |
| `/data/logs/` | Server logs (auto-rotated: max 10 files × 10 MB) |

**Full backup** (requires brief downtime):

```bash
docker-compose stop
cp -r /path/to/jhentai-data /backup/jhentai-$(date +%Y%m%d)
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
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | A Docker Hub **Access Token** (not your password) |

To create a Docker Hub token: Docker Hub → Account Settings → Security → New Access Token.

**Image tags published:**

| Tag | When |
|---|---|
| `latest` | Every push to `master` |
| `x.y.z` | On version tag, e.g. `v8.0.12` |
| `x.y` | On version tag (minor alias) |
| `master` | Every push to `master` branch |

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

**Permission denied writing to `/data`**  
→ Set `PUID`/`PGID` to match your host user, or run: `chown -R 1000:1000 /path/to/data-volume`

**WebSocket disconnects / downloads page shows no live updates**  
→ Ensure your reverse proxy passes `Upgrade`/`Connection` headers (see Nginx example above)

**Downloads interrupted after restart**  
→ Active downloads are automatically resumed when the server starts

**ExHentai content not loading**  
→ Go to **Settings → Site** and switch to **ExHentai**, then log in with valid ExHentai cookies
