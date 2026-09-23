---
name: prepare-review
description: >-
  Prepare px-keyboard changes as an exact review candidate: create or validate
  Conventional Commits, rebase onto origin/main, add the isolated SemVer bump,
  verify the build, and stop without pushing. Use before /review, not for
  landing.
---

# Prepare px-keyboard changes for review

Use this skill when the user asks to prepare the current changes for review.
Produce the complete candidate that a reviewer can approve, including the final
version commit. Do not push any ref, land the change, or treat preparation as
approval.

## Sources of truth

- `AGENTS.md` defines the repository's commit, version, and verification rules.
- `VERSION` is the only source of truth for the project version.
- `justfile` defines the supported build commands and workstation overrides.
- `origin/main` is the review candidate's base.

## Workflow

1. Establish the requested scope and base.
   - Inspect `git --no-optional-locks status --short`, the staged and unstaged
     diffs, the current branch, configured remotes, and recent commits.
   - Include only the changes the user asked to prepare. Preserve ignored files,
     generated build output, and unrelated work.
   - If unrelated edits cannot be separated safely, stop and ask one focused
     scope question.
   - Run `git fetch origin main` before recording the base SHA. If fetching
     fails, stop; do not prepare a candidate against a stale base.

2. Create or validate the semantic change commit(s).
   - If currently on `main`, create a topic branch such as
     `review/<short-description>`. Never commit the candidate directly on
     `main`.
   - Stage only the requested files and create focused, non-interactive
     Conventional Commits in the form `type(scope): description`; the scope is
     optional.
   - If the requested changes are already committed, do not duplicate them.
     Validate every commit that will be in `origin/main..HEAD`.
   - Require at least one semantic change commit; a release commit by itself is
     not a review candidate.
   - The release commit described below is the only exception when validating
     change-commit headers.
   - Keep secrets, ignored files, and generated output out of every commit.

3. Rebase before calculating the version.
   - Require a clean index and worktree, then rebase the topic branch onto the
     fetched `origin/main`.
   - Stop and ask the user on any conflict. Do not resolve rebase conflicts
     automatically.
   - If the rebase changes a commit SHA, that is expected at this stage because
     review has not started.

4. Calculate and commit exactly one version increment.
   - Read the base version from `git show origin/main:VERSION`, not from a
     working-tree copy that may already contain a bump.
   - Inspect all semantic change commits in `origin/main..HEAD`, excluding an
     existing commit named `chore(release): bump version to X.Y.Z`.
   - Apply the highest required increment once for the complete candidate:
     - while `VERSION_MAJOR` is `0`, a `BREAKING CHANGE:` footer or `!` before
       the commit header's colon increments `MINOR`;
     - from `1.0.0` onward, a breaking change increments `MAJOR`;
     - `feat` increments `MINOR`;
     - every other commit type increments `PATCH`.
   - Reset lower components after a `MAJOR` or `MINOR` increment. Keep
     `VERSION_TWEAK = 0` and `EXTRAVERSION` empty.
   - Create the final isolated commit
     `chore(release): bump version to X.Y.Z`. It may change only `VERSION`.
   - If a release commit already exists, require it to be the final commit and
     validate its base version, increment, message, and file scope. Reuse it
     only when all are correct.
   - Never rewrite an existing release or change commit if it is reachable from
     a remote ref. Stop and report that published history needs an explicit
     recovery decision.

5. Verify the exact candidate.
   - The official verification target is `nrf54l15dk/nrf54l05/cpuapp`.
   - Use `just rebuild-54` when the candidate changes `prj.conf`,
     `app.overlay`, `CMakeLists.txt`, or the Objective-Z transpiler. Otherwise
     use `just build-54`.
   - If the normal command fails only because the Delta worktree makes the
     `justfile` workspace-relative `ZEPHYR_BASE` invalid, retry the selected
     build directly with the workspace-aware environment. First run
     `just clean`, because the failed configuration can leave an incomplete
     cache that prevents `west` from regenerating:
     - incremental:
       `ZEPHYR_BASE="$(west topdir)/deps/zephyr" ZEPHYR_SDK_INSTALL_DIR="$HOME/.local/zephyr-sdk-1.0.1" west build -b nrf54l15dk/nrf54l05/cpuapp -d build . --`
     - pristine:
       `ZEPHYR_BASE="$(west topdir)/deps/zephyr" ZEPHYR_SDK_INSTALL_DIR="$HOME/.local/zephyr-sdk-1.0.1" west build -p always -b nrf54l15dk/nrf54l05/cpuapp -d build . --`
   - Treat any other failed build as a preparation blocker.
   - After verification, require a clean index and worktree and confirm that
     the release commit is still `HEAD`.
   - Do not report hardware behavior as verified unless the relevant board was
     actually flashed and exercised.

6. Present the candidate for review and stop.
   - Report the exact topic-tip SHA, base SHA, resulting version, commit list,
     changed files, and verification command and result.
   - State explicitly that nothing was pushed and that the candidate is ready
     for `/review`.
   - Remind the user that any amendment, rebase, or additional commit
     invalidates a later approval and requires preparation and review again.

## Safety rules

- Never push to `local`, `origin`, or any other remote.
- Never force-push or rewrite a commit reachable from a remote ref.
- Never bypass a failed fetch, rebase, or build.
- Never combine the version change with another file.
- Never claim that preparation or a passing build is review approval.
