# JHenTai — Docker 部署指南

[English](https://github.com/OYcedar/JHenTai/blob/master/DOCKER.md) | 简体中文 | [한국어](https://github.com/OYcedar/JHenTai/blob/master/DOCKER_kr.md)

---

## 目录

- [快速开始](#快速开始)
- [首次登录](#首次登录)
- [配置说明](#配置说明)
- [本地画廊扫描](#本地画廊扫描)
- [数据备份](#数据备份)
- [反向代理](#反向代理)
- [Docker Hub 手动发布](#docker-hub-手动发布)
- [安全说明](#安全说明)
- [常见问题](#常见问题)

---

## 快速开始

### 从 Docker Hub 拉取

镜像只使用 `**x.y.z-hhh**` 这一种标签形式：

- `**x.y.z**`：与 `pubspec.yaml` 的 `version:` 中 `**+` 前面**一致。
- `**hhh`**：**三位小写十六进制**（000–fff），对应本 Docker fork 的十进制版本号 **0–4095**（见仓库根下 `**docker/fork_revision`**）。

示例：fork 版本号为 `310` 时，`310` → 十六进制 `136`，故标签为 `**8.0.12-136**`（在应用版本为 `8.0.12` 的前提下）。

**不再提供 `latest`**，请在 compose / Unraid 里写死具体标签。

```bash
docker pull hemumoe/jhentai:8.0.12-136
```

**docker-compose.yml**（推荐）：

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

### 从源码构建

```bash
git clone https://github.com/OYcedar/JHenTai.git
cd JHenTai
docker-compose up -d --build
```

---

## 首次登录

在浏览器中打开 `http://<服务器IP>:8080`，首次访问时会要求输入 **API Token**。在容器日志中查看：

```bash
docker logs jhentai
```

找到类似以下的一行：

```
Generated new API token: a3f9c2...
```

在浏览器的设置页面输入该 Token，它会保存在 `localStorage` 中，之后无需重复输入。

---

## 配置说明

### 环境变量


| 变量                    | 默认值        | 说明                |
| --------------------- | ---------- | ----------------- |
| `JH_DATA_DIR`         | `/data`    | 数据目录（数据库、日志、配置、本地画廊目录；若设置了 `JH_DOWNLOAD_DIR` 则**不含**下载文件） |
| `JH_DOWNLOAD_DIR`     | `{JH_DATA_DIR}/download` | 画廊/归档下载根目录（其下为 `gallery/<gid>/`、`archive/<gid>/`）。可指向独立挂载，例如 Unraid 将 `/mnt/user/media/comics/download` 挂到容器内 `/downloads` 并设为 `JH_DOWNLOAD_DIR=/downloads`。 |
| `JH_PORT`             | `8080`     | HTTP 监听端口         |
| `JH_HOST`             | `0.0.0.0`  | 绑定地址              |
| `JH_WEB_DIR`          | `/app/web` | Web 前端静态文件目录      |
| `JH_EXTRA_SCAN_PATHS` | *（空）*      | 逗号分隔的额外本地画廊扫描路径   |
| `PUID`                | `1000`     | 映射卷文件所有者的用户 ID    |
| `PGID`                | `1000`     | 映射卷文件所有者的组 ID     |


### PUID / PGID（Unraid）

将 `PUID` 和 `PGID` 设置为与 Unraid 用户匹配，以确保下载文件的权限正确：

```yaml
environment:
  - PUID=99
  - PGID=100
```

### 下载目录与配置分离（Unraid 示例）

配置与数据库仍在 appdata，漫画下载放到媒体盘：

```yaml
volumes:
  - /mnt/user/appdata/jhentai:/data
  - /mnt/user/media/comics/download:/downloads
environment:
  - JH_DOWNLOAD_DIR=/downloads
  - PUID=99
  - PGID=100
```

---

## 本地画廊扫描

将媒体目录挂载到容器中，并通过 `JH_EXTRA_SCAN_PATHS` 注册：

```yaml
volumes:
  - /mnt/user/media/manga:/media/manga:ro
  - /mnt/user/media/doujinshi:/media/doujinshi:ro
environment:
  - JH_EXTRA_SCAN_PATHS=/media/manga,/media/doujinshi
```

服务器启动时会自动扫描这些路径，并在 Web UI 的**本地画廊**页面中展示。

---

## 数据备份

默认以 `/data` 为主卷；若配置了 **`JH_DOWNLOAD_DIR`**，下载内容在该路径下（不再使用 `/data/download/`）：


| 路径                     | 内容                            |
| ---------------------- | ----------------------------- |
| `/data/db.sqlite`      | 数据库：设置、EH Cookie、下载任务状态       |
| `{JH_DOWNLOAD_DIR}`（默认 `/data/download/`） | 已下载的画廊图片及解压后的归档文件             |
| `/data/local_gallery/` | 直接放置在容器中的本地画廊                 |
| `/data/logs/`          | 服务器日志（自动轮转：最多 10 个文件 × 10 MB） |


**完整备份**（需短暂停机）：

```bash
docker-compose stop
docker run --rm -v jhentai-data:/data -v $(pwd)/backup:/backup alpine \
  tar czf /backup/jhentai-$(date +%Y%m%d).tar.gz -C / data
docker-compose start
```

**仅备份数据库**（零停机，SQLite 在线备份）：

```bash
docker exec jhentai sqlite3 /data/db.sqlite ".backup /data/db_backup.sqlite"
```

---

## 反向代理

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name jhentai.example.com;

    # 普通 HTTP 流量
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket — 实时下载进度必需
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

Caddy 会自动处理 WebSocket 升级，无需额外配置。

### Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.jhentai.rule=Host(`jhentai.example.com`)"
  - "traefik.http.services.jhentai.loadbalancer.server.port=8080"
```

---

## Docker Hub 手动发布

本 fork **不再**通过 GitHub Actions 自动推送镜像。在已执行 **`docker login`** 的机器上本地构建并推送（或使用你自建的 CI）。面向 Cursor 的检查清单见 [`skills/docker-hub-publish/SKILL.md`](skills/docker-hub-publish/SKILL.md)。

**一键脚本**（在仓库根目录执行，标签为 `x.y.z-hhh`）：

- **Linux / macOS / Git Bash：** `chmod +x scripts/docker-hub-publish.sh && ./scripts/docker-hub-publish.sh`
- **Windows PowerShell：** `powershell -ExecutionPolicy Bypass -File scripts/docker-hub-publish.ps1`

若 Docker Hub 命名空间不是 **`hemumoe`**，请设置环境变量 **`DOCKERHUB_USERNAME`**。

**标签规则：**

| 段 | 来源 |
| --- | --- |
| `x.y.z` | `pubspec.yaml` 里 `version:` 中 **`+` 前面** |
| `hhh` | **`docker/fork_revision`** 的十六进制（三位小写，十进制 **0–4095**）。无该文件时用 `pubspec` 的 **`+` 后构建号** |

**Fork 版本号：** 发布新镜像前修改 **`docker/fork_revision`**（单行十进制）。例：十进制 **311** → 十六进制 **`137`** → 标签 **`8.0.12-137`**（在应用版本为 `8.0.12` 时）。

**登录：** 使用 Docker Hub → Account Settings → Security 中的 **Access Token** 配合 `docker login`（勿用账户密码）。

**删除 Docker Hub 上的旧标签**（如 `latest`、裸 `8.0.12`、`8.0`、`*-web`、`docker-web-`* 等）：

```bash
export DOCKERHUB_USERNAME=hemumoe
export DOCKERHUB_TOKEN=你的_Hub_Access_Token
chmod +x scripts/dockerhub-delete-tags.sh
./scripts/dockerhub-delete-tags.sh latest 8.0.12 8.0 8.0.12-web 8.0-web docker-web-48f728fb
```

请按 [Hub 标签页](https://hub.docker.com/r/hemumoe/jhentai/tags) 实际存在的名称调整参数；也可在网页上手动删除。

---

## 安全说明

- 除 `/api/health` 外，所有 API 端点均需要 `Authorization: Bearer <token>` 请求头
- Token 在首次启动时自动生成，并存储在 SQLite 数据库中
- 代理端点仅允许访问 EH/EX 域名（防止 SSRF 攻击）
- 本地文件端点仅限于已配置的扫描路径（防止路径遍历攻击）
- Web 前端将 Token 存储在浏览器的 `localStorage` 中

---

## 常见问题

**容器无法启动**
→ 查看日志：`docker logs jhentai`

**Unraid 上反复重启（exit 255）**
→ 不要使用 Hub 上的 `latest`（本仓库已不维护该标签）；请使用 **`x.y.z-hhh`** 具体标签并重新拉取镜像。数据目录映射到 `/mnt/user/...` 时，容器内 `chown` 可能失败，新版本 entrypoint 会记录 **WARNING** 后继续启动；请保证宿主机上该目录对 **`PUID`/`PGID`**（Unraid 常用 `99:100`）可写。若在 compose 中设置了 `HTTP_PROXY`/`HTTPS_PROXY`，请保留 `NO_PROXY` 中的 `127.0.0.1,localhost`，否则健康检查或本地请求可能异常。

**写入 `/data` 时提示权限不足**
→ 将 `PUID`/`PGID` 设置为与宿主机用户匹配，或执行：`chown -R 1000:1000 /path/to/data-volume`

**WebSocket 断开 / 下载页面没有实时进度**  
→ 确认反向代理正确转发了 `Upgrade`/`Connection` 请求头（参见上方 Nginx 示例）

**服务重启后下载中断**  
→ 服务器启动时会自动恢复之前正在进行的下载任务

**ExHentai 内容无法加载**  
→ 进入 **设置 → 站点**，切换至 **ExHentai**，并使用有效的 ExHentai Cookie 登录

**Unraid / 局域网直连：封面能出，画廊内页或阅读器大图 500（`*.hath.network` 报 `HandshakeException`）**  
Web 端大量图片走 **`/api/proxy/image`** 由**服务端代拉**。封面常在 **`ehgt.org`**（可能正常），而分页大图多在 **H@H 节点**（`*.hath.network`）。若服务端日志或 500 正文中出现 **`HandshakeException: Connection terminated during handshake`**，说明**容器内**与该主机的 **TLS 握手失败**（IPv6 路径、MTU、防火墙、证书链等），一般不是 Flutter Web 本身问题。

1. **H@H 优先 IPv4 为可选项**：默认对 **`*.hath.network`** 使用常规 HTTPS（与 EH 一致）。若确认 **`HandshakeException`** 且怀疑仅 IPv6 到 H@H 异常，再在容器环境变量中设置 **`JH_HATH_PREFER_IPV4=1`**（或 `true`）并重启。本地 / Windows 上 Docker **一般不要设置**。
2. **在容器内自检**（把主机名换成失败 URL 中的 H@H 节点）：  
   `openssl s_client -connect 节点名.hath.network:443 -servername 节点名.hath.network`  
   或 `curl -vI 'https://节点名.hath.network/…'`  
   若容器内失败而 Unraid 宿主机成功，重点查 **Docker 网络**、**IPv6**、**MTU**、**防火墙** 对桥接/自定义网络的策略。
3. **反代与 414**：排查时可先 **直连容器端口**（如 **`8088:8080`**）。很长的大图 URL 应使用 **`POST /api/proxy/image`**（URL 放在 JSON body），避免查询串过长触发前置 Nginx/Caddy 的 **414 URI Too Large**。
4. **Token**：画廊相关请求会通过查询参数 **`?token=<API Token>`** 调用图片代理；该路由**不依赖** `Authorization` 头。若缩略图 401/403，请在 **设置** 中确认 Token 正确。
5. **EX 画廊**：需在服务端配置 **有效的 ExHentai Cookie**；仅有 EH Cookie 无法访问仅 EX 可见的内容。