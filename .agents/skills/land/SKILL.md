---
name: land
description: >-
  Land px-keyboard changes only after the user explicitly requests landing
  through Delta Land Changes, /land, or equivalent language. Do not use this
  skill for review, setup, preparation-only work, or passing checks without a
  landing request.
metadata:
  delta-action: land
---

# Land px-keyboard changes

Use this skill only for an explicit landing request. A visible `/land`
invocation, the Delta Land Changes button, or a direct request to land or merge
the current changes is already permission to run this workflow; do not ask the
user again whether they want to land. Stop only for genuine blockers, ambiguous
scope, unrelated work that cannot be preserved safely, failed verification, push
denial, or merge/rebase conflicts.

This repository lands directly: make a local topic branch, rebase it onto the
latest `origin/main`, merge it into local `main`, push `main` to Delta's `local`
remote first so the user's project checkout is updated, then push `main` to
`origin`. Do not open a pull request or wait for CI; this repository currently
has no CI workflow configured, and the project owner specified that PRs are not
the landing path.

## Sources for project-specific commands

- `justfile:7` defines the board as `nrf52833dk/nrf52833`.
- `justfile:18-26` defines the normal workspace-derived `ZEPHYR_BASE` and
  Zephyr SDK location.
- `justfile:44-46` defines the normal build command:
  `west build -b {{ board }} -d {{ build_dir }} . -- {{ flags }}`.
- `CMakeLists.txt:9-19` resolves the Objective-Z module from `west topdir` and
  finds Zephyr from `$ZEPHYR_BASE`; this supports the Delta-worktree fallback
  when the `justfile` workspace-relative `ZEPHYR_BASE` points at the wrong
  parent directory.

## Workflow

1. Establish the requested landing scope.
   - Inspect `git --no-optional-locks status --short` and the diff.
   - Include only the changes the user asked to land.
   - If unrelated edits are present and cannot be cleanly separated, stop and
     ask the user which changes belong in this landing.
   - Preserve ignored local files and generated build artifacts; do not add
     them.

2. Prepare a topic branch and commit.
   - If already on a topic branch for the requested change, use it.
   - If on `main`, create a local topic branch with a clear name, for example
     `land/<short-description>`.
   - Stage only the requested files.
   - Create a non-interactive commit with an appropriate concise message.
   - If the requested changes are already committed, identify the commit range
     instead of making a duplicate commit.

3. Update from the destination.
   - Run `git fetch origin main`.
   - Rebase the topic branch onto `origin/main`.
   - Conflict preference: pause and ask the user on any rebase or merge
     conflict. Do not resolve conflicts automatically.
   - If rebase succeeds, continue with the rebased commit(s). If it fails for a
     reason other than conflicts, stop and report the blocker.

4. Verify the exact rebased change locally.
   - First try the normal command:
     `just build`
   - If that fails because the Delta worktree path makes the `justfile`
     workspace-relative `ZEPHYR_BASE` invalid, retry with the workspace-aware
     fallback:
     `ZEPHYR_BASE="$(west topdir)/deps/zephyr" ZEPHYR_SDK_INSTALL_DIR="$HOME/.local/zephyr-sdk-1.0.1" west build -b nrf52833dk/nrf52833 -d build . --`
   - Treat a failed build as a landing blocker. Do not push.

5. Merge to local `main`.
   - Ensure the topic branch contains the verified commit(s).
   - Check out `main`.
   - Fast-forward `main` to `origin/main` if possible.
   - Merge the rebased topic branch into `main`. Prefer a fast-forward merge
     when available; if Git requires a non-fast-forward merge after a successful
     rebase, stop and explain why instead of inventing a merge strategy.
   - If conflicts occur, pause and ask the user.

6. Update the user's local project checkout first.
   - Inspect `git remote -v` and confirm there is a `local` remote. In Delta,
     this is the backlink to the user's primary project checkout.
   - Push `main` to `local` before pushing to `origin`:
     `git push local main:main`
   - If this push is rejected, stop and report the blocker. Do not push to
     `origin` while the user's local project checkout would remain behind.
   - Verify that `local/main` now points at or contains the landed commit, for
     example with `git ls-remote local refs/heads/main` or an equivalent
     inspected ref.

7. Push and verify the upstream destination.
   - Push `main` to `origin` only after the `local` remote has been updated and
     verified.
   - Fetch or inspect `origin/main` after the push and verify that the landed
     commit is reachable from `origin/main`.
   - Successful landing means the requested change is present on both
     `local/main` and `origin/main`, not merely committed locally, verified
     locally, or pushed to a topic branch.

8. Report the outcome.
   - In the conversation, summarize the landed commit short SHA, destination,
     and verification command.
   - If running in a subthread and `report_subthread_status` is available, also
     report the result to the parent:
     - Use `status: "success"` only after verifying the requested commit is on
       both `local/main` and `origin/main`.
     - Use `status: "failure"` for failed builds, conflicts, push denial,
       ambiguous scope, or any blocker that prevents landing.
     - Keep the title short, such as `Landed on main`, `Blocked by build`,
       `Merge conflicts`, or `Push blocked`.
     - Keep the description to one short line with the short SHA when known and
       the verification result. Omit CI links because this repository has no CI.

## Safety rules

- Never force-push.
- Never rewrite published `main`.
- Do not bypass failed local verification.
- Do not publish secrets or read credential values.
- Do not treat skill installation, branch publication, or a passing build as a
  successful landing.
- If the user’s requested scope is unclear, ask one focused question rather
  than guessing.
