# JHenTai — Docker 배포 가이드

[English](https://github.com/OYcedar/JHenTai/blob/master/DOCKER.md) | [简体中文](https://github.com/OYcedar/JHenTai/blob/master/DOCKER_cn.md) | 한국어

---

## 목차

- [빠른 시작](#빠른-시작)
- [첫 로그인](#첫-로그인)
- [설정](#설정)
- [로컬 갤러리 스캔](#로컬-갤러리-스캔)
- [백업](#백업)
- [리버스 프록시](#리버스-프록시)
- [Docker Hub CI/CD](#docker-hub-cicd)
- [보안](#보안)
- [문제 해결](#문제-해결)

---

## 빠른 시작

### Docker Hub에서 가져오기

태그는 **`x.y.z-hhh`** 형식만 사용합니다.

- **`x.y.z`**: `pubspec.yaml`의 `version:`에서 `+` 앞 semver.
- **`hhh`**: fork 전용 십진수 **0–4095**를 **소문자 16진수 3자리**로 표시(`docker/fork_revision` 참고).

예: fork 버전 `310` → `310` = `0x136` → **`8.0.12-136`**.

**`latest` 태그는 없습니다.** compose/Unraid에서 위와 같이 명시하세요.

```bash
docker pull hemumoe/jhentai:8.0.12-136
```

**docker-compose.yml**（권장）:

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

### 소스 코드에서 빌드

```bash
git clone https://github.com/OYcedar/JHenTai.git
cd JHenTai
docker-compose up -d --build
```

---

## 첫 로그인

브라우저에서 `http://<서버IP>:8080`을 열면 최초 접속 시 **API 토큰** 입력 화면이 표시됩니다. 토큰은 컨테이너 로그에서 확인할 수 있습니다:

```bash
docker logs jhentai
```

아래와 같은 줄을 찾으세요:

```
Generated new API token: a3f9c2...
```

브라우저의 설정 페이지에 이 토큰을 입력하면 `localStorage`에 저장되어 이후 재입력이 필요하지 않습니다.

---

## 설정

### 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `JH_DATA_DIR` | `/data` | 데이터 디렉토리 (데이터베이스, 다운로드, 로그) |
| `JH_PORT` | `8080` | HTTP 포트 |
| `JH_HOST` | `0.0.0.0` | 바인드 주소 |
| `JH_WEB_DIR` | `/app/web` | 웹 프론트엔드 정적 파일 디렉토리 |
| `JH_EXTRA_SCAN_PATHS` | *(비어 있음)* | 로컬 갤러리 스캔을 위한 추가 경로 (쉼표로 구분) |
| `PUID` | `1000` | 마운트된 볼륨의 파일 소유자 사용자 ID |
| `PGID` | `1000` | 마운트된 볼륨의 파일 소유자 그룹 ID |

### PUID / PGID (Unraid)

다운로드된 파일의 권한이 올바르게 설정되도록 `PUID`와 `PGID`를 Unraid 사용자와 일치시키세요:

```yaml
environment:
  - PUID=99
  - PGID=100
```

---

## 로컬 갤러리 스캔

미디어 디렉토리를 컨테이너에 마운트하고 `JH_EXTRA_SCAN_PATHS`로 등록하세요:

```yaml
volumes:
  - /mnt/user/media/manga:/media/manga:ro
  - /mnt/user/media/doujinshi:/media/doujinshi:ro
environment:
  - JH_EXTRA_SCAN_PATHS=/media/manga,/media/doujinshi
```

서버가 시작될 때 해당 경로를 자동으로 스캔하며, 웹 UI의 **로컬 갤러리** 페이지에서 확인할 수 있습니다.

---

## 백업

모든 데이터는 `/data` 볼륨 아래에 저장됩니다:

| 경로 | 내용 |
|---|---|
| `/data/db.sqlite` | 데이터베이스: 설정, EH 쿠키, 다운로드 작업 상태 |
| `/data/download/` | 다운로드된 갤러리 이미지 및 압축 해제된 아카이브 |
| `/data/local_gallery/` | 컨테이너에 직접 배치된 로컬 갤러리 |
| `/data/logs/` | 서버 로그 (자동 순환: 최대 10개 파일 × 10 MB) |

**전체 백업** (잠시 중단 필요):

```bash
docker-compose stop
docker run --rm -v jhentai-data:/data -v $(pwd)/backup:/backup alpine \
  tar czf /backup/jhentai-$(date +%Y%m%d).tar.gz -C / data
docker-compose start
```

**데이터베이스만 백업** (무중단, SQLite 온라인 백업):

```bash
docker exec jhentai sqlite3 /data/db.sqlite ".backup /data/db_backup.sqlite"
```

---

## 리버스 프록시

### Nginx

```nginx
server {
    listen 443 ssl;
    server_name jhentai.example.com;

    # 일반 HTTP 트래픽
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket — 실시간 다운로드 진행 상황에 필수
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

Caddy는 WebSocket 업그레이드를 자동으로 처리합니다.

### Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.jhentai.rule=Host(`jhentai.example.com`)"
  - "traefik.http.services.jhentai.loadbalancer.server.port=8080"
```

---

## Docker Hub CI/CD

GitHub Actions 워크플로 `.github/workflows/docker-publish.yml`은 다음 상황에서 자동으로 이미지를 빌드하고 Docker Hub에 푸시합니다:

- `v*` 형식의 태그가 푸시된 경우 (버전 릴리스, 예: `v8.0.12`)
- 서버 또는 웹 프론트엔드 소스 파일이 변경된 커밋이 `master`에 푸시된 경우

**GitHub 저장소에 다음 Secrets를 설정해야 합니다:**

| Secret | 값 |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub **Access Token** (비밀번호 아님) |

Docker Hub 토큰 생성: Docker Hub → Account Settings → Security → New Access Token.

**게시되는 이미지 태그:**

| 태그 | 트리거 조건 |
|---|---|
| `x.y.z-hhh` | 워크플로 실행 시마다; `hhh`는 fork 리비전의 16진수(`docker/fork_revision` 또는 `pubspec`의 `+` 빌드 번호) |

**구 태그 삭제**(`latest`, `8.0.12`, `8.0`, `*-web` 등): `scripts/dockerhub-delete-tags.sh` 및 [DOCKER.md](https://github.com/OYcedar/JHenTai/blob/master/DOCKER.md)의 예시를 참고하세요.

---

## 보안

- `/api/health`를 제외한 모든 API 엔드포인트는 `Authorization: Bearer <token>` 헤더가 필요합니다
- 토큰은 최초 실행 시 자동으로 생성되어 SQLite 데이터베이스에 저장됩니다
- 프록시 엔드포인트는 EH/EX 도메인만 허용합니다 (SSRF 방지)
- 로컬 파일 엔드포인트는 설정된 스캔 경로로만 제한됩니다 (경로 탐색 공격 방지)
- 웹 프론트엔드는 토큰을 브라우저의 `localStorage`에 저장합니다

---

## 문제 해결

**컨테이너가 시작되지 않음**  
→ 로그 확인: `docker logs jhentai`

**`/data` 쓰기 권한 오류**  
→ `PUID`/`PGID`를 호스트 사용자와 일치시키거나 실행: `chown -R 1000:1000 /path/to/data-volume`

**WebSocket 연결 끊김 / 다운로드 페이지에 실시간 진행 상황이 표시되지 않음**  
→ 리버스 프록시가 `Upgrade`/`Connection` 헤더를 올바르게 전달하는지 확인하세요 (위의 Nginx 예제 참조)

**재시작 후 다운로드가 중단됨**  
→ 서버 시작 시 진행 중이던 다운로드가 자동으로 재개됩니다

**ExHentai 콘텐츠가 로드되지 않음**  
→ **설정 → 사이트**로 이동하여 **ExHentai**로 전환하고 유효한 ExHentai 쿠키로 로그인하세요
