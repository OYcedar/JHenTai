---
name: jhentai-docker-local-deploy
description: >-
  Local JHenTai-Docker: deploy by running docker compose from repo root — default
  is `docker compose up -d --build`. Use when the user asks for local Docker deploy,
  to verify after edits, or to auto-deploy locally when work in this repo is done.
---

# JHenTai — 本地部署（Docker Compose）

## 原则

**本地部署 = 在仓库根目录直接起 compose。** 常规迭代不需要额外步骤；改完代码后一条命令即可。

## 何时执行

- 本仓库（含根目录 `Dockerfile`、`docker-compose.yml`）**实现或修改完成后**，用户要本地跑起来、或明确说本地部署 / compose。
- 用户说「部署一下」「本地起一下」等 — 按下面默认命令执行。

**不跑**：只要方案/文档、用户禁止 Docker、或纯只读问答。

## 默认命令（仓库根目录）

PowerShell：用 **`;`** 链接命令，不要用 **`&&`**。

```powershell
Set-Location H:\JHenTai-Docker
docker compose up -d --build
```

（路径按用户实际仓库根目录替换。）

- 容器名：**`jhentai`**
- 默认访问：**`http://localhost:8080`**

## 可选：怀疑缓存坏掉时再全量重建

```powershell
docker compose build --no-cache; docker compose up -d
```

日常**不要**默认加 `--no-cache`，除非构建明显用了陈旧层。

## 简单验收

```powershell
docker compose ps
docker compose logs jhentai --tail 80
```

## 失败时

- **端口占用**：改 `docker-compose.yml` 主机端口或停掉占用进程。
- **构建失败**：看 build 日志；修 Dart/Flutter/服务端编译后再 `docker compose up -d --build`。
- **Linux 权限/卷**：查 `PUID`/`PGID`；Windows 查 Docker Desktop 文件共享。

## 与其他 skill 的关系

- 推 **Docker Hub**（多架构）：用 [jhentai-docker-hub-publish](../jhentai-docker-hub-publish/SKILL.md)。
- 本 skill **仅本地**，不涉及 registry。

## Agent 收尾检查

1. 用户未禁止执行命令。
2. `Set-Location` 到含 `docker-compose.yml` 的根目录。
3. 执行 **`docker compose up -d --build`**（默认）；必要时再用 `--no-cache` 那条。
4. 汇报退出码；若异常，贴 `docker compose logs jhentai` 末尾若干行。
