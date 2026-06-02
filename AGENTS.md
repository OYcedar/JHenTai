# AGENTS.md

## Local agent rules

- Work on the `docker` branch only unless the user explicitly asks for a release merge.
- Keep related cross-page UX work in one scoped change and one commit. For example, if adding or refactoring "scroll to top", scan all relevant Web pages first, implement the shared behavior once, and commit it once.
- Do not create repeated tiny commits for the same UI pattern across pages.
- For Web/App experience parity work, check `docs/WEB_APP_PARITY_AUDIT.md` first. Update the matrix, choose one high-value theme package, and avoid low-value "feedback only" commits unless they are part of that theme.
- Before committing, check `git rev-list --count master..docker`.
- After every 10 commits on `docker`, merge `docker` into `master`, push the Docker image, increment `docker/fork_revision`, and update README / Docker image tags through the publish script.
- If fewer than 10 commits have accumulated, push only the `docker` branch and do not push a Docker image.
- Commit messages in this repository must be written in Chinese.
