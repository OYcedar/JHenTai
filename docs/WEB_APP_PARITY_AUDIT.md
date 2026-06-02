# Web/App Experience Parity Audit

This document tracks the Docker/Web fork against the upstream native App experience. It exists to prevent scattered "find work" changes: new Web/App parity work should start here, pick one high-value theme, and land as one scoped commit.

Last audited: 2026-06-02

## Summary

The Docker/Web fork already covers most high-value App workflows:

- Gallery discovery: home, popular, watched, favorites, ranklist, advanced filters.
- Gallery detail: favorite, rating, comments, torrent/archive/H@H related actions, statistics, version/update affordances.
- Reading: online, downloaded, archive, local, continuous/fit-width/double-column style Web reader controls.
- Downloads: gallery/archive tasks, search, regex search, category filter, sorting, grouping, priorities, batch actions, restore.
- Data portability: Web export, App-compatible `JHenTaiConfig` export, Web/App JSON import, cloud config import/upload.
- Management pages: history, search history, quick search, block rules, EH tag sets, local galleries, Docker paths/logs/security.

The remaining gaps are either platform-specific App features or larger backend work, not small UI-feedback tasks.

## Feature Matrix

| Area | App Support | Docker/Web Support | Status | Notes |
| --- | --- | --- | --- | --- |
| Home gallery list | Yes | Yes | Covered | Web includes section switching and two-pane layout. |
| Popular | Yes | Yes | Covered | Web exposes Popular in drawer and dashboard. |
| Watched | Yes | Yes | Covered | Web supports watched section and tag style highlighting. |
| Favorites | Yes | Yes | Covered | Web supports favorites and sort/filter controls. |
| Ranklist | Yes | Yes | Covered | Web supports all-time/year/month/yesterday ranklist modes. |
| Search filters | Yes | Yes | Covered | Web quick search also stores filters and target sections. |
| Search history | Yes | Yes | Covered | Web supports history overlay, hide/show, translation, clear. |
| Quick search | Yes | Yes | Covered | Web supports add/edit/delete/reorder/run. |
| Gallery detail | Yes | Yes | Covered | Web covers favorite, rating, comments, tag actions, torrents, archives, stats. |
| Reader layouts | Yes | Yes | Covered | Web has continuous, fit-width, double column, wheel controls, local/archive/downloaded modes. |
| Download tasks | Yes | Yes | Covered | Web has gallery/archive tabs, search, filters, batch actions, group and priority editing. |
| Local galleries | Yes | Yes | Covered | Web supports scan roots, directory browsing, search, grid/list, local reader. |
| History | Yes | Yes | Covered | Web supports search, pagination, grid/list, delete/clear. |
| Block rules | Yes | Yes | Covered | Web has grouped rule management and import/export support. |
| EH tag sets | Yes | Yes | Covered | Web manages watched/hidden tags and tag set colors through server proxy. |
| Settings | Yes | Yes | Covered | Web maps settings to Docker-compatible pages, including network, read, style, download, performance, security, Docker. |
| Data export/import | Yes | Yes | Covered | Web can export JSON, export App-compatible `JHenTaiConfig`, and import both formats. |
| Cloud config sync | Yes | Yes | Covered | Web supports share code lookup, import, upload, delete, download. |
| Super-resolution | Yes, desktop/local only | No Web backend API | Deferred | Native feature depends on local model files and subprocess execution. A Docker implementation needs server APIs, model management, output storage, and reader/download integration. |
| Native package updates | Yes | No | Not in scope | This fork is Docker/Web-only and does not publish native app packages. |
| Native OS integrations | Yes | Browser-limited | Not in scope | File associations, native windows, system notifications, local model picker, and desktop-only paths are not Web-equivalent. |

## Priority Backlog

### P1: Super-resolution for Docker/Web

This is the largest genuine App/Web parity gap, but it is not a small frontend task.

Required work:

- Server API for model configuration, model download/status, GPU selection, job start/pause/delete/status.
- Persistent job table or migration path compatible with Docker data storage.
- Output file routing so the Web reader can switch between original and super-resolved images.
- Download page badges/actions matching native task behavior.
- Safety checks for CPU/GPU availability and disk usage in Docker.

Do not implement this as scattered UI-only stubs. It should be one backend-plus-frontend project.

### P2: Web visual QA and navigation polish

Use this only for substantial issues found with screenshots or reproduction steps, such as layout breakage, unreadable controls, or broken workflows. Do not create commits that only add generic failure snackbars.

### P3: Documentation and release hygiene

Keep Docker-only scope, image tag/version rules, and Web/App parity notes current. This is valid work when it prevents future duplicated or low-value commits.

## Development Rule

Before starting new Web/App parity work:

1. Check this matrix first.
2. Add or update the row if a real gap is found.
3. Choose one theme package.
4. Implement, verify, and commit that theme as one Chinese commit.
5. Avoid repeated tiny commits for the same pattern across pages.

