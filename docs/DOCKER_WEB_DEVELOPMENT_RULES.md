# Docker/Web Development Rules

This repository is a Docker/Web-only fork of JHenTai. Use this file as the
portable rule sheet when developing from a new machine or a fresh agent session.

## Branching

- Develop on the `docker` branch.
- Do not work directly on `master` unless the user explicitly asks for a release
  merge or publish.
- Before committing on `docker`, check:

  ```bash
  git rev-list --count master..docker
  ```

- If `master..docker` is fewer than 10 commits, push only `docker`.
- After every 10 Docker-branch commits, run the release flow:
  merge `docker` into `master`, publish the Docker image, update versioned image
  tags, and push both branches.

## Commit Rules

- Commit messages must be written in Chinese.
- Keep one related Web/Docker theme in one scoped commit.
- Do not create repeated small commits for the same UI pattern across pages.
- Do not include secrets, tokens, cookies, private paths, or personal device
  details in commits, README, screenshots, logs, or docs.

## Scope

- This fork maintains the browser-based Docker experience, server runtime,
  Docker image, and deployment documentation.
- Native Android/iOS/desktop package publishing is not the target of this fork.
- For Web/App parity work, review `docs/WEB_APP_PARITY_AUDIT.md` first. Choose a
  high-value theme and avoid scattered low-value UI-only feedback commits.
- Do not revisit previously settled "scroll to top" work unless the user
  explicitly asks for it.

## Verification

Use verification proportional to the change. Common checks:

```bash
git diff --check
dart format --set-exit-if-changed <changed-dart-files>
dart analyze <changed-dart-files>
flutter build web --release --no-wasm-dry-run --target lib/src/main_web.dart
docker build -t jhentai:<topic>-local .
```

For server-only work, also analyze the changed files under `server/lib`.
For Docker runtime work, run a temporary container and verify:

```bash
curl -fsS http://127.0.0.1:8080/api/health
```

## Local Docker Testing

- When building a new local test image, deploy the new image for validation.
- After a successful local deployment, remove the old local JHenTai test image.
- Do not remove unrelated Docker images from other projects.
- Keep local test tags descriptive, for example `jhentai:<topic>-local`.

## Docker Hub Release

Use the tracked publish skill/checklist:

- `skills/docker-hub-publish/SKILL.md`
- `scripts/docker-hub-publish.sh`
- `scripts/docker-hub-publish.ps1`

Release requirements:

- Publish tags must use `x.y.z-hhh`.
- The publish script increments `docker/fork_revision`.
- The publish script updates README / DOCKER / compose image tags.
- After a successful publish, commit those version/tag changes in Chinese.
- After a successful publish, remove old local JHenTai Docker images and keep
  only the current versioned tag plus `latest`.

## Upstream Updates

- Pull or merge upstream only when requested.
- Preserve this fork's Docker/Web-only scope and deployment rules when resolving
  upstream changes.
- After upstream merges, verify Web build and Docker runtime paths before
  release.
