# Contributing

## Workflow

Watcher uses GitHub flow on `main`; changes arrive as pull requests from forks.

1. Fork `mkemalgokce/watcher`, clone your fork, and branch from `main`: `feat/…`, `fix/…`, `refactor/…`, `test/…`,
   `docs/…`, `ci/…` or `chore/…`.
2. Run `make bootstrap` once to install the tools and the git hooks.
3. Push to your fork and open a pull request against `main` using the template. Its title must be a conventional commit of
   at most 66 characters; it becomes the squash commit (GitHub appends ` (#N)`) and the changelog entry.
4. The maintainer squash-merges it after review.

`main` is protected: a pull request needs passing `checks`, `swift` and `pr-title` checks (`swift` is skipped when only docs change) and a review from the
code owner (@mkemalgokce, see `.github/CODEOWNERS`) before it can be merged.

## Make targets

| Target | Does |
|---|---|
| `make bootstrap` | Installs the Brewfile tools, the pinned SwiftLint and SwiftFormat binaries (`scripts/install-tools.sh`) and the lefthook git hooks |
| `make format` / `make format-check` | Formats with SwiftFormat / fails on unformatted code |
| `make lint` | SwiftLint, strict; violations recorded in `.swiftlint-baseline.json` are tolerated, new ones fail |
| `make lint-baseline` | Rewrites the baseline; only to drop violations that were fixed, never to accept new ones |
| `make lint-analyze` / `make lint-analyze-baseline` | SwiftLint's unused-code analyzer (a full build, a few minutes; CI runs it nightly) against `.swiftlint-analyze-baseline.json` / rewrites that baseline |
| `make test` | Every test target but `WatcherInteractionTests`, which drive the process's windows and so run alone |
| `make test-unit` / `make test-integration` / `make test-smoke` | `WatcherCoreTests` + `WatcherUITests` + `WatcherCLITests` / `WatcherIntegrationTests` / every `*SmokeTests` suite (the engine, and the built `watcher-cli`) |
| `make test-e2e` / `make test-snapshot` / `make test-interaction` | `WatcherE2ETests` / `WatcherSnapshotTests` / `WatcherInteractionTests` (skipped without the Accessibility permission) |
| `make snapshots-record` | Rewrites the snapshot references for this macOS |
| `make coverage` | Unit and integration tests with coverage, gated by `scripts/coverage-thresholds.txt`; CI runs it with `test-snapshot` and `test-e2e` |
| `make changelog` | Regenerates `CHANGELOG.md` with git-cliff |
| `make dmg` | Builds `dist/Watcher-$(VERSION).dmg` (default 0.0.0) like a release, signed ad hoc and not notarized |

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`.

- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`.
- Scope: the area (`core`, `proxy`, `tls`, `tools`, `export`, `ui`, `cli`, `mcp`) or `repo`, `ci`, `deps`.
- Subject: English, imperative, lowercase first letter, no trailing period, at most 66 characters. No `Co-Authored-By` trailer and no tool attribution.
- Breaking changes: `type(scope)!: subject` or a `BREAKING CHANGE:` footer.

The `commit-msg` hook runs `scripts/check-commit-msg.sh`.

## Test-driven development

Every change starts with a failing test.

1. **List edge cases** as parameter tables: empty, boundary, malformed and huge input, cancellation, concurrency, failure paths.
2. **Red.** Run the test and see it fail for the expected reason.
3. **Green.** Write the minimum code.
4. **Refactor** with `make format lint test` green.

## Releases

Only the maintainer releases. Pushing a `v*` tag starts `.github/workflows/release.yml`; the build waits for approval in the
`release` environment, then signs the DMG with the project's Developer ID, notarizes and staples it, and publishes the
release with notes from git-cliff. The signing and notary secrets live only in that environment.

The DMG window's background is `tools/dmg/background.svg`; after editing it, run `tools/dmg/render-background.sh`
(needs `librsvg` from the Brewfile) to rebuild the 1x and 2x `background.tiff`.

## Design rules

- SOLID, separation of concerns, DRY.
- A protocol exists only at a seam with a second implementation; a test double or preview mock counts.
- New code reaches side effects (network, disk, keychain, processes, `UserDefaults`, pasteboard) only from `Live*` adapters and gets them injected. SwiftLint enforces this for new code.
- No new singletons or global mutable state; no direct `Date()`, `UUID()` or randomness in tested code.
- Views only render; state and intents live in view models.
- Colors and typography come from `Sources/WatcherUI/Design`.

## Tests

New tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), one suite per subject in `<Subject>Tests.swift`,
with test names that read as behaviour sentences. A test file sits at the path of its subject's source:
`Sources/<Module>/<Folder>/<Subject>.swift` is tested in `Tests/<Target>/<Folder>/<Subject>Tests.swift`. A subject too
large for one file keeps one top-level suite and splits it into `<Subject>Tests+<Aspect>.swift` files, each holding
`extension <Subject>Tests { struct <Aspect> { … } }`. The kind of test is chosen by its target:

| Target | Holds |
|---|---|
| `WatcherCoreTests`, `WatcherUITests`, `WatcherCLITests` | Unit tests: logic, view models and CLI commands, no network or external tools |
| `WatcherIntegrationTests` | A real proxy on loopback, local origins, external tools, WebKit; `SmokeTests` is the fast subset |
| `WatcherE2ETests` | The built `watcher-cli` run as a process with its own `WATCHER_HOME` |
| `WatcherSnapshotTests` | Text and image snapshots (swift-snapshot-testing) |
| `WatcherInteractionTests` | The real window driven through the Accessibility API; local only |

Builders (`Flow.fixture`, `RequestRecord.fixture`, `ResponseRecord.fixture`), the proxy `Harness`, local origins, test
doubles, async helpers and the Swift Testing tags live in `Tests/WatcherTestSupport`, one type per file. Support code
never asserts and never imports XCTest: it returns values or throws `TestSupportError`. Use tags such as `.timing`,
`.network` and `.externalTool`, and gate tools with `.enabled(if: ExternalTool.python3.isAvailable)`.

Snapshots: prefer text snapshots, which are the same on every macOS. Image references are stored per macOS major
version in `__Snapshots__/macOS-<major>/`; an image suite skips on a macOS without references when recording is off. A
missing reference is recorded locally (the test fails once, then passes); CI sets `SNAPSHOT_TESTING_RECORD=never`, so
there it fails instead. Commit references only for screens whose change you have looked at.

## Test doubles

| Name | Does |
|---|---|
| `…Stub` | Returns canned values |
| `…Spy` | Records calls |
| `…Fake` | Working simplified implementation, such as an in-memory file system |
| `…Mock` | Verifies expectations; only when a spy is not enough |

## Adding a module

1. Write its first test in `Tests/<Module>Tests/<Folder>/<Type>Tests.swift`, mirroring `Sources/<Module>/<Folder>/<Type>.swift`.
2. Add the target and its test target to `Package.swift`.
3. Add `Sources/<Module> <percent>` to `scripts/coverage-thresholds.txt`.
