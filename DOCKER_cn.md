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
- [Docker Hub 自动发布](#docker-hub-自动发布)
- [安全说明](#安全说明)
- [常见问题](#常见问题)

---

## 快速开始

### 从 Docker Hub 拉取

```bash
docker pull hemumoe/jhentai:latest
```

**docker-compose.yml**（推荐）：

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

| 变量 | 默认值 | 说明 |
|---|---|---|
| `JH_DATA_DIR` | `/data` | 数据目录（数据库、下载文件、日志） |
| `JH_PORT` | `8080` | HTTP 监听端口 |
| `JH_HOST` | `0.0.0.0` | 绑定地址 |
| `JH_WEB_DIR` | `/app/web` | Web 前端静态文件目录 |
| `JH_EXTRA_SCAN_PATHS` | *（空）* | 逗号分隔的额外本地画廊扫描路径 |
| `PUID` | `1000` | 映射卷文件所有者的用户 ID |
| `PGID` | `1000` | 映射卷文件所有者的组 ID |

### PUID / PGID（Unraid）

将 `PUID` 和 `PGID` 设置为与 Unraid 用户匹配，以确保下载文件的权限正确：

```yaml
environment:
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

所有数据均存储在 `/data` 卷中：

| 路径 | 内容 |
|---|---|
| `/data/db.sqlite` | 数据库：设置、EH Cookie、下载任务状态 |
| `/data/download/` | 已下载的画廊图片及解压后的归档文件 |
| `/data/local_gallery/` | 直接放置在容器中的本地画廊 |
| `/data/logs/` | 服务器日志（自动轮转：最多 10 个文件 × 10 MB） |

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

## Docker Hub 自动发布

GitHub Actions 工作流 `.github/workflows/docker-publish.yml` 会在以下情况自动构建并推送镜像到 Docker Hub：

- 推送 `v*` 格式的 Tag（版本发布，例如 `v8.0.12`）
- 向 `master` 分支推送了涉及服务端或 Web 前端源码的提交

**需要在 GitHub 仓库中配置以下 Secrets：**

| Secret | 值 |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub **Access Token**（非密码） |

创建 Docker Hub Token：Docker Hub → Account Settings → Security → New Access Token。

**发布的镜像标签：**

| 标签 | 触发时机 |
|---|---|
| `latest` | 每次向 `master` 推送 |
| `x.y.z` | 版本 Tag 触发，例如 `v8.0.12` |
| `x.y` | 版本 Tag 触发（次版本别名） |
| `master` | 每次向 `master` 分支推送 |

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

**写入 `/data` 时提示权限不足**  
→ 将 `PUID`/`PGID` 设置为与宿主机用户匹配，或执行：`chown -R 1000:1000 /path/to/data-volume`

**WebSocket 断开 / 下载页面没有实时进度**  
→ 确认反向代理正确转发了 `Upgrade`/`Connection` 请求头（参见上方 Nginx 示例）

**服务重启后下载中断**  
→ 服务器启动时会自动恢复之前正在进行的下载任务

**ExHentai 内容无法加载**  
→ 进入 **设置 → 站点**，切换至 **ExHentai**，并使用有效的 ExHentai Cookie 登录
