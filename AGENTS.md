# Repository guidance

## Project

PX Keyboard is heap-free Bluetooth LE HID firmware written in Objective-Z for
Zephyr. The primary target is `nrf54l15dk/nrf54l05/cpuapp`; the
`nrf52833dk/nrf52833` target is also supported. The repository normally lives
beside the Objective-Z module and `deps/zephyr` in an Objective-Z west workspace.

Read `README.md` for setup and behavior. Read `docs/OZ-IDIOMS.md` before changing
the architecture. In particular:

- subsystems are singletons and communicate through zbus channels;
- the publisher owns its channel and observers register in their own files;
- observers are asynchronous unless inline execution is specifically justified;
- every subsystem implements `-getDescription:maxLength:`;
- comments beside Zephyr configuration and stack sizes preserve the reason for
  those choices.

## Build and verification

- `just build-54` performs the normal incremental nRF54L05 build.
- `just rebuild-54` performs a pristine build and is required after changing
  `prj.conf`, `app.overlay`, `CMakeLists.txt`, or the Objective-Z transpiler.
- `just build` and `just rebuild` are the supported nRF52833 equivalents.
- Hardware behavior must not be reported as verified unless it was actually
  flashed and exercised on the relevant board.

Build paths and SDK defaults are workstation-specific and can be overridden
through the variables documented in `README.md` and `justfile`.

## Commits and versions

Use Conventional Commits (`type(scope): description`) so every change has a
semantic commit. Keep commits focused; do not mix unrelated changes.

`VERSION` is the only source of truth for the project version. Normal releases
use SemVer `MAJOR.MINOR.PATCH`; keep `VERSION_TWEAK` at `0` and `EXTRAVERSION`
empty.

Every landing increments the version exactly once, according to the highest
impact among its change commits:

- while `VERSION_MAJOR` is `0`, a `BREAKING CHANGE:` footer or `!` before the
  commit header's colon increments `MINOR`;
- from `1.0.0` onward, a breaking change increments `MAJOR`;
- `feat` increments `MINOR`;
- all other commit types increment `PATCH`.

Reset lower components to zero when incrementing `MAJOR` or `MINOR`. Put the
version edit in a final, isolated commit named
`chore(release): bump version to X.Y.Z`. That commit may change only `VERSION`
and is excluded when calculating the next bump.

Do not hard-code the current version in documentation or source. Zephyr derives
`APP_VERSION_STRING` from `VERSION`.

## Landing

Use `.agents/skills/prepare-review/SKILL.md` to prepare the complete candidate
before review. Preparation creates or validates the semantic change commits,
rebases onto `origin/main`, adds the final isolated version commit, verifies the
build, reports the exact candidate tip, and stops without pushing.

Only land after an explicit landing request and at least one recorded human
approval of the exact candidate tip. Follow `.agents/skills/land/SKILL.md`;
it is the authoritative procedure.

Approval covers the complete rebased candidate, including the isolated version
commit. Any amended commit, rebase, or additional change invalidates approval
and requires verification and approval again.

Landing must not create, amend, rebase, or otherwise change the approved
candidate. If preparation or approval is missing or stale, stop and return to
the preparation and review workflow.

Landing pushes the approved Delta `main` directly to `origin/main`. If the
user's local `main` is still clean and unchanged from its preflight state, fetch
`origin/main` in that repository and fast-forward local `main`. Completion
requires the Delta `main`, local `main`, and remote `origin/main` to resolve to
the same commit.
