---
name: land
description: >-
  Land an already prepared and human-approved px-keyboard candidate after an
  explicit request through Delta Land Changes, /land, or equivalent language.
  Do not use this skill to prepare commits, perform review, or pass checks
  without a landing request.
metadata:
  delta-action: land
---

# Land px-keyboard changes

Use this skill only for an explicit landing request. A visible `/land`
invocation, the Delta Land Changes button, or a direct request to land or merge
the current changes is already permission to run this workflow; do not ask the
user again whether they want to land. Stop only for genuine blockers, ambiguous
scope, stale preparation or approval, an invalid candidate, a changed
destination, push denial, or unsafe local synchronization.

This repository lands a candidate already produced by `/prepare-review` and
approved through review. Landing must not change that candidate: validate the
exact approved tip, fast-forward Delta's `main`, push it directly to `origin`,
then fetch and fast-forward the user's local `main` if it has not changed since
preflight. Do not open a pull request or wait for CI; this repository currently
has no CI workflow configured, and the project owner specified that PRs are not
the landing path.

## Candidate contract

- `/prepare-review` creates or validates the semantic change commits, rebases
  them onto `origin/main`, creates the final isolated version commit, verifies
  the build, and reports the exact candidate tip without pushing.
- A human review approves that exact tip.
- This skill validates and publishes the approved commit graph without
  creating, amending, rebasing, squashing, or otherwise rewriting it.

## Workflow

1. Identify the immutable candidate and its approval.
   - Require a clean index and worktree. Landing never commits outstanding
     changes.
   - Record the current `HEAD` as the candidate tip and inspect its complete
     commit range and diff.
   - Require a recorded successful `/prepare-review` result for this exact SHA,
     including the verification command and result.
   - Require at least one explicit human approval of this exact SHA. A landing
     request, approval of an earlier diff, or a changes-requested verdict does
     not count.
   - Record the candidate SHA, prepared base SHA, resulting version, verification
     result, and approver for the final report.

2. Confirm that the destination has not changed.
   - Run `git fetch origin main`. If it fails, stop.
   - Require the fetched `origin/main` SHA to equal the base recorded by
     `/prepare-review`.
   - Require the candidate to be a strict descendant of `origin/main`, suitable
     for a fast-forward.
   - If the destination advanced, stop. Do not rebase during landing; run
     `/prepare-review`, verification, and review again.

3. Validate the prepared commit graph without changing it.
   - Require every change commit in `origin/main..HEAD` to follow Conventional
     Commits.
   - Require `HEAD` to be the sole release commit, named
     `chore(release): bump version to X.Y.Z`, and require it to change only
     `VERSION`.
   - Recalculate the required version increment from the base `VERSION` and the
     change commits using the rules in `AGENTS.md`. Require the release commit's
     contents and message to match exactly.
   - Require `VERSION_TWEAK = 0` and an empty `EXTRAVERSION`.
   - If any validation fails, stop and return to `/prepare-review`; do not fix
     the candidate in the landing workflow.

4. Preflight the local repository.
   - Resolve `git remote get-url local` and require it to identify the user's
     local px-keyboard Git repository. Inspect that repository without changing
     or deleting user work.
   - Require its checked-out branch to be `main`, its index and worktree to be
     clean, and its `main` to equal the destination `origin/main` SHA established
     by the post-approval fetch. Do not rely on a possibly stale remote-tracking
     ref. Stop if any condition fails.
   - Record the local `main` SHA and clean status. Recheck both before updating
     the local repository after the upstream push.
   - Confirm the local repository has an `origin` remote for the intended
     upstream.

5. Fast-forward Delta's `main` to the approved candidate.
   - Retain the approved candidate SHA before switching branches.
   - Check out `main`.
   - Fast-forward `main` to `origin/main`, then fast-forward it to the approved
     candidate SHA using `git merge --ff-only`.
   - Require `main` to equal the approved SHA. If either fast-forward fails,
     stop; do not create a merge commit.

6. Push Delta's `main` directly to `origin`.
   - Immediately before pushing, inspect the remote `origin/main` again. If it
     differs from the prepared base, stop and return to preparation and review.
   - Push normally from the Delta worktree:
     `git push origin main:main`
   - Never force-push. If the push is rejected, stop and report the blocker.
   - Fetch or inspect `origin/main` after the push and require it to equal
     Delta's `main`.

7. Fast-forward the user's local `main` and verify synchronization.
   - Resolve the user's checkout through `git remote get-url local`.
   - Before changing it, require its branch, `main` SHA, index, and worktree to
     match the state recorded during preflight. If another person or agent
     changed it, stop without overwriting their work and report that the
     upstream landing succeeded but local synchronization is incomplete.
   - From the user's local checkout, fetch `origin/main`, then fast-forward:
     `git fetch origin main`
     `git merge --ff-only origin/main`
   - Do not reset, force-update, or discard local work if the fast-forward
     fails.
   - Fetch `origin/main` in the Delta worktree after the update so comparisons
     do not use stale remote-tracking refs.
   - Require Delta's `main`, the user's local `main`, and the remote
     `origin/main` to resolve to exactly the same commit. Also require the
     user's local checkout to remain clean and on `main`.
   - Successful landing means all three repositories are synchronized, not
     merely that the candidate is committed, built, or present on a topic
     branch.

8. Report the outcome.
   - In the conversation, summarize the landed commit short SHA, destination,
     resulting version, approver, and verification command.
   - If running in a subthread and `report_subthread_status` is available, also
     report the result to the parent:
     - Use `status: "success"` only after verifying the requested commit is on
       both the user's local `main` and `origin/main`.
     - Use `status: "failure"` for stale preparation or approval, destination
       changes, push denial, or any blocker that prevents landing.
     - Keep the title short, such as `Landed on main`, `Approval stale`,
       `Destination changed`, or `Push blocked`.
     - Keep the description to one short line with the short SHA when known and
       the verification result. Omit CI links because this repository has no CI.

## Safety rules

- Never force-push.
- Never rewrite published `main`.
- Never create, amend, rebase, squash, or cherry-pick candidate commits.
- Do not land without recorded successful preparation of the exact candidate.
- Do not land without approval of the exact final candidate.
- Do not combine the version edit with any other change.
- Do not overwrite a local checkout that changed after preflight.
- Do not publish secrets or read credential values.
- Do not treat skill installation, branch publication, or a passing build as a
  successful landing.
- If the user’s requested scope is unclear, ask one focused question rather
  than guessing.
