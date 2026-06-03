---
name: docker-web-development
description: >-
  Repository-specific development workflow for this JHenTai Docker/Web fork:
  branch rules, Chinese commits, verification, local Docker cleanup, and release
  behavior.
---

# Docker/Web development workflow

Use this skill before making code, documentation, release, or Docker changes in
this repository.

## Source of truth

Read and follow:

- `AGENTS.md`
- `docs/DOCKER_WEB_DEVELOPMENT_RULES.md`
- `skills/docker-hub-publish/SKILL.md` when publishing Docker Hub images

## Required behavior

- Work on `docker` unless the user explicitly asks for a release merge.
- Use Chinese commit messages.
- Keep related Web/Docker UX work in one scoped commit.
- Check `git rev-list --count master..docker` before deciding whether to publish.
- If fewer than 10 commits have accumulated, push only `docker`.
- When the user explicitly requests merge/publish, merge to `master`, run the
  Docker Hub publish script, commit the version/doc updates, push both branches,
  and clean old local JHenTai images.

## Verification defaults

Run checks appropriate to the changed files:

```bash
git diff --check
dart format --set-exit-if-changed <changed-dart-files>
dart analyze <changed-dart-files>
flutter build web --release --no-wasm-dry-run --target lib/src/main_web.dart
docker build -t jhentai:<topic>-local .
```

For local Docker validation, deploy the new image and check:

```bash
curl -fsS http://127.0.0.1:8080/api/health
```

## Safety

- Do not expose secrets, tokens, cookies, private paths, or personal device
  details.
- Do not delete unrelated Docker images.
- Do not change native-app release behavior unless explicitly requested.
