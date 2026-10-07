# slint_dart

https://github.com/listepo/slint_dart

Slint UI toolkit ↔ Flutter integration.

| # | Status | Priority | Complexity | Readiness | Agent |
| --- | --- | --- | --- | --- | --- |
| T4 | todo | P3 | 2 | 0% | |

### T4. SonarCloud through the shared pyrlyn/ci workflow

`.github/workflows/sonarcloud.yml` (66 lines) is a hand-kept copy of pyrlyn/ci's reusable
`sonarcloud.yml`, which names slint_dart among the copies it replaces. Turn it into a thin
caller. Reference: pyrlyn/ci `docs/reusable-workflows.md` ("sonarcloud.yml").

**GitHub Actions is disabled on this repository** (2026-10-08). Nothing runs until the creator
turns it back on. Ask before doing so: it also starts `ci.yml`, `pages.yml` and `publish.yml`.

Steps:

1. Replace the job's steps with `uses:
   pyrlyn/ci/.github/workflows/sonarcloud.yml@c875cd763ad0c4abbd936e480be5752330d3b66b # main
   2026-10-07` (a newer pyrlyn/ci main is fine, always by full 40-character SHA, never `@main`).
2. Keep the caller's `on:` (pull requests to main with `ready_for_review`, pushes to main,
   `workflow_dispatch`), `concurrency` (`${{ github.workflow }}-${{ github.ref }}`, cancel) and
   top-level `permissions: contents: read`. The `sonarcloud` job keeps its id and grants
   `contents: read`, `pull-requests: read` and `actions: write` (the shared job cancels the run
   on failure, and GitHub refuses a nested job that asks for more than its caller grants).
   Drafts are skipped by the shared workflow itself.
3. Secret: `secrets: SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}`, passed explicitly (no `secrets:
   inherit`). It already exists in the repository; without it every step skips with a notice,
   as today. Organization and project key stay in `sonar-project.properties` (leave the
   `organization` and `project-key` inputs empty).
4. Toolchain through mise instead of `subosito/flutter-action`: `mise: true`,
   `mise-install-args: flutter` (mise.toml pins `flutter = "latest"`; just and Hugo are not
   needed for the scan). If mise's Flutter is slower than the action's cache, record the times
   in the PR.
5. `setup-command: dart pub get` (resolved packages let the scanner's Dart analyzer see the
   dependencies). No `coverage-command`: the current workflow uploads no coverage. `soft-fail`
   stays at its default `true`, like the old `continue-on-error`. Note that a failing
   `dart pub get` now fails the job, where the old step was `continue-on-error`.
6. Update `docs/sonarcloud-setup.md` (what the workflow is, how to make it blocking:
   `soft-fail: false`) in the same change.

Done means: `actionlint .github/workflows/sonarcloud.yml` is clean; the workflow has no
`steps:` and calls pyrlyn/ci's `sonarcloud.yml` by full SHA; with Actions enabled and
`SONAR_TOKEN` set, the `sonarcloud / sonarcloud` job on the pull request runs `dart pub get`
and the scan, and SonarCloud shows an analysis for that pull request; a draft pull request
skips it.
