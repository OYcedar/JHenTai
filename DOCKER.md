# JHenTai — Docker Deployment Guide

English | [简体中文](https://github.com/OYcedar/JHenTai-Docker/blob/docker/DOCKER_cn.md) | [한국어](https://github.com/OYcedar/JHenTai-Docker/blob/docker/DOCKER_kr.md)

---

> This repository is the **Docker/Web-only fork** of JHenTai. It maintains the browser UI, server runtime, Docker image, and deployment workflow only. Native Android/iOS/desktop app packages are not release targets of this fork.

## Table of Contents

- [Quick Start](#quick-start)
- [First Login](#first-login)
- [Setup and Upgrade Checklist](#setup-and-upgrade-checklist)
- [Configuration](#configuration)
- [Local Gallery Scanning](#local-gallery-scanning)
- [Backup](#backup)
- [Reverse Proxy](#reverse-proxy)
- [Docker Hub publish (manual)](#docker-hub-publish-manual)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Pull from Docker Hub

Images are tagged **`x.y.z-hhh`** only:

- **`x.y.z`** — app semver from `pubspec.yaml` (`version:` before `+`).
- **`hhh`** — **three lowercase hex digits** (000–fff) for this Docker fork’s revision, decimal **0–4095** (see `docker/fork_revision`).

Example: `8.0.12+309` with fork revision `310` → **`8.0.12-136`** (`310` = `0x136`).

The publish scripts also push `latest`, but compose / Unraid examples must pin an explicit `x.y.z-hhh` tag.

```bash
docker pull hemumoe/jhentai:8.0.14-15a
```

**docker-compose.yml** (recommended):

```yaml
services:
  jhentai:
    image: hemumoe/jhentai:8.0.14-15a
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
git clone https://github.com/OYcedar/JHenTai-Docker.git
cd JHenTai-Docker
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

## Setup and Upgrade Checklist

After the first login, open **Settings → Web/Docker → Setup checklist**. The page reads local runtime state only and does **not** automatically probe EH/EX, H@H, Docker Hub, or any other external endpoint.

Use it after first deployment and after image upgrades to confirm:

- API token and EH cookie state.
- Data, download, log, temp, and SQLite access.
- Proxy routing, especially the H@H route.
- Explicit Docker tag / fork revision instead of long-term `latest` usage.
- SQLite backup entry before imports, restores, or image upgrades.
- Failed download summary and the troubleshooting workbench link.
- GPU/Vulkan and installed model readiness for image super-resolution.

If a network or H@H problem is suspected, open **Settings → Web/Docker → Troubleshooting workbench** and run the active probes manually.

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
| `JH_SUPER_RESOLUTION_BINARY` | *(empty)* | Advanced debug override for the super-resolution executable path. Most users should download model packages from the Web UI instead. |
| `JH_SUPER_RESOLUTION_MODEL_MIRROR` | *(empty)* | Optional mirror base URL for super-resolution model ZIP downloads. The server appends the upstream ZIP filename to this base URL. |
| `PUID` | `1000` | User ID for file ownership on mapped volumes |
| `PGID` | `1000` | Group ID for file ownership on mapped volumes |
| `HTTP_PROXY` / `HTTPS_PROXY` | *(empty)* | Outbound proxy used by the backend when it requests EH/EX/H@H. For `https://` targets, set `HTTPS_PROXY=http://proxy-host:port`. |
| `JH_HATH_PROXY` | *(empty)* | Outbound proxy for `*.hath.network` only. When set, it overrides `NO_PROXY`; use it when EH/EX works through the proxy but H@H image hosts do not. |
| `NO_PROXY` / `no_proxy` | `127.0.0.1,localhost,::1` appended by entrypoint | Hosts that bypass the proxy. Do not include `e-hentai.org`, `exhentai.org`, `*.ehgt.org`, or `*.hath.network`, otherwise detail and image requests bypass the proxy. |

### PUID / PGID (Unraid)

Set these to match your Unraid user so that downloaded files are owned by the correct user:

```yaml
environment:
  - PUID=99
  - PGID=100
```

---

## Image super resolution (GPU first)

Docker/Web includes an optional image super-resolution center under **Settings → Web/Docker → Image super resolution**. It runs external `Real-CUGAN ncnn Vulkan` / `Real-ESRGAN ncnn Vulkan` tools. Model packages are stored under `/data/super_resolution/models`, and generated images are stored under `/data/super_resolution/output`; original downloads are not overwritten.

Notes:

1. The feature is **GPU/Vulkan first**. If no GPU is detected, the page shows a warning. CPU-only mode is experimental and is not recommended for large NAS workloads.
2. Official Ubuntu prebuilt packages are treated as the amd64 path in this fork. arm64 NAS users may need to provide a compatible custom executable and debug with `JH_SUPER_RESOLUTION_BINARY`.
3. Super-resolution output can be much larger than source images. Check free space before starting large jobs.
4. Intel/AMD integrated GPUs usually require passing `/dev/dri` into the container. AMD/Intel integrated GPU NAS devices usually use this path:

```yaml
services:
  jhentai:
    devices:
      - /dev/dri:/dev/dri
```

5. If the self-check still reports no GPU, or logs show permission errors for `/dev/dri/renderD128`, add the host render/video group IDs to the container. These IDs vary by NAS. Check them on the host first:

```bash
stat -c '%n %g' /dev/dri/renderD128 /dev/dri/card0
```

Then add the matching numeric IDs to compose, for example:

```yaml
services:
  jhentai:
    devices:
      - /dev/dri:/dev/dri
    group_add:
      - "109" # replace with the group ID of /dev/dri/renderD128
      - "44"  # replace with the group ID of /dev/dri/card0 if needed
```

6. NVIDIA GPUs require NVIDIA Container Toolkit on the host and the appropriate `--gpus all` / Compose GPU configuration.
7. If your NAS or reverse proxy environment cannot expose GPU devices, the page can still be used for diagnostics and model management, but large CPU-only jobs are discouraged.
8. “Auto super-resolve after download” is disabled by default. Enable it only after GPU self-check passes, models are installed, and enough free disk space is available.

### Model download and manual import

Open **Settings → Web/Docker → Image super resolution** to manage models. Clicking **Download** starts a server-side download and the model card shows progress, retry state, and the latest error.

If GitHub downloads are slow or blocked by the NAS network, either set `JH_SUPER_RESOLUTION_MODEL_MIRROR` to a trusted mirror base URL, or download the matching upstream ZIP manually and click **Import ZIP** for that model. The server installs model packages through a temporary directory first, rejects packages that do not contain the expected executable, and keeps the previous installed model intact when validation fails.

The model page never enables CPU-only work by default. Installing a model also does not start jobs automatically; automatic super-resolution after downloads must be enabled separately.

---

## Optional Archive Bot / Archive-at-Home parsing

Docker/Web can optionally use a third-party archive parsing service for archive downloads. Open **Settings → Web/Docker → Download → Archive Bot / Archive-at-Home** to configure:

- Protocol: `Archive-at-Home` or `EH-ArBot`.
- API address.
- API key.
- Manual balance test and check-in.

This feature is **disabled by default**. Existing archive downloads continue to use the official EH archive path unless a task is explicitly started or switched with the Bot parse source. API keys are stored in the local SQLite config table, are not shown back in the Web UI, and are redacted from diagnostics.

Use this only if you trust the selected third-party service. The server does not register accounts, host API keys, or automatically fall back from official archive parsing to Bot parsing.

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

## Docker Hub publish (manual)

This fork does **not** use GitHub Actions to push Docker images. Build and push from your machine (or any CI you control) after **`docker login`**. A Cursor-oriented checklist lives in [`skills/docker-hub-publish/SKILL.md`](skills/docker-hub-publish/SKILL.md).

Every publish script run increments **`docker/fork_revision`** and updates README / compose image tags before pushing. Commit those file changes after a successful image push. After the push, remove old local JHenTai images and keep only the current `x.y.z-hhh` tag plus `latest`. Set **`DOCKER_SKIP_VERSION_BUMP=1`** only when intentionally re-pushing the current tag.

**One-shot scripts** (from the repo root; pushes **`x.y.z-hhh`** and **`latest`**):

- **Linux / macOS / Git Bash:** `chmod +x scripts/docker-hub-publish.sh && ./scripts/docker-hub-publish.sh`
- **Windows PowerShell:** `powershell -ExecutionPolicy Bypass -File scripts/docker-hub-publish.ps1`

Set **`DOCKERHUB_USERNAME`** if your Hub namespace is not **`hemumoe`**.

**Tag format:**

| Part | Source |
|---|---|
| `x.y.z` | `pubspec.yaml` `version:` before `+` |
| `hhh` | Lowercase hex of **`docker/fork_revision`** (decimal **0–4095**). If the file is missing, the number after **`+`** in `pubspec.yaml` is used. |

**Fork revision:** The publish scripts increment **`docker/fork_revision`** automatically when cutting a new Hub image. Example: revision **311** → hex **`137`** → tag **`8.0.12-137`** (with semver `8.0.12`).

**Docker Hub token:** create an **Access Token** under Docker Hub → Account Settings → Security if you use `docker login` with token auth (not your account password).

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
→ Do not deploy with the moving `latest` tag; pull an explicit **`x.y.z-hhh`** tag. If `/data` is on `/mnt/user/...`, in-container `chown` may fail; the entrypoint logs a **WARNING** and continues—ensure the host path is writable by your **`PUID`/`PGID`** (often `99:100` on Unraid). With `HTTP_PROXY`/`HTTPS_PROXY`, keep `127.0.0.1` and `localhost` in **`NO_PROXY`**.

**Permission denied writing to `/data`**  
→ Set `PUID`/`PGID` to match your host user, or run: `chown -R 1000:1000 /path/to/data-volume`

**WebSocket disconnects / downloads page shows no live updates**  
→ Ensure your reverse proxy passes `Upgrade`/`Connection` headers (see Nginx example above)

**Downloads interrupted after restart**  
→ Active downloads are automatically resumed when the server starts

**ExHentai content not loading**  
→ Go to **Settings → Site** and switch to **ExHentai**, then log in with valid ExHentai cookies

**`http_proxy` is set in Docker, gallery lists work, but gallery details do not**
→ Detail pages, thumbnails, and reader images are fetched by the backend server. Check:

1. Set **`HTTPS_PROXY`** for `https://` targets. If only `HTTP_PROXY/http_proxy` is set, new builds also use it as a fallback for HTTPS requests.
2. If only `*.hath.network` misses the proxy, set **`JH_HATH_PROXY=http://proxy-host:port`**. It forces H@H image hosts through that proxy even if `NO_PROXY` accidentally matches them.
3. Do **not** put `e-hentai.org`, `exhentai.org`, `*.ehgt.org`, or `*.hath.network` in `NO_PROXY`; that makes normal detail requests bypass the proxy.
4. Keep `NO_PROXY` to local addresses such as `127.0.0.1,localhost,::1`. The entrypoint appends these automatically so health checks and local API calls stay direct.
5. Rebuild/restart after compose changes: `docker compose up -d --build`, or pull the new image and run `docker compose up -d`.

**Unraid / direct LAN: cover loads but in-gallery / reader images 500 (`HandshakeException` on `*.hath.network`)**  
The web UI loads many images via **`/api/proxy/image`**. Covers often use **`ehgt.org`** (which may work) while page images use **H@H hosts** (`*.hath.network`). If the **server** logs or the 500 body mention **`HandshakeException: Connection terminated during handshake`**, TLS to the H@H node is failing inside the container (IPv6 routing, MTU, firewall, or CA issues—not the Flutter web app).

1. **H@H IPv4 preference is opt-in**: by default the server uses normal HTTPS to **`*.hath.network`** (same as EH). If you see **`HandshakeException`** and suspect broken IPv6 to H@H only, set **`JH_HATH_PREFER_IPV4=1`** (or `true`) in the container environment and restart. Local / Windows Docker usually should **leave this unset**.
2. **Verify inside the container** (replace host with one from a failing URL):  
   `openssl s_client -connect YOURNODE.hath.network:443 -servername YOURNODE.hath.network`  
   or `curl -vI 'https://YOURNODE.hath.network/…'`  
   If this fails in the container but works on the Unraid host, inspect **Docker networking**, **IPv6**, **MTU**, and **firewall** rules for the bridge.
3. **Bypass reverse-proxy limits**: map the container port directly (e.g. **`8088:8080`**) when testing. Long image URLs need **`POST /api/proxy/image`** with the URL in the JSON body so the query string stays short—otherwise you may see **414 URI Too Large** from Nginx/Caddy in front of the app.
4. **Auth**: gallery pages call the proxy with **`?token=<API token>`** (query param). The **`Authorization`** header is not required for that route; keep the token in **Settings** if thumbnails return 401/403.
5. **EX galleries**: ensure **ExHentai** cookies are valid in server settings; EH cookies alone will not load EX-only content.
