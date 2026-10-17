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
| `make test` | Every test, including `WatcherInteractionTests` (they skip without the Accessibility permission) |
| `make test-unit` | Every test except `WatcherInteractionTests`; CI runs it with coverage on every pull request |
| `make coverage` | `test-unit` with coverage, gated by `scripts/coverage-thresholds.txt` |
| `make changelog` | Regenerates `CHANGELOG.md` with git-cliff |
| `make dmg` | Builds `dist/Watcher-$(VERSION).dmg` (default 0.0.0) like a release, signed ad hoc and not notarized |

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): subject`.

- Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`.
- Scope: the area (`core`, `proxy`, `tls`, `tools`, `export`, `ui`, `cli`, `mcp`) or `repo`, `ci`, `deps`.
- Subject: English, imperative, lowercase first letter, no trailing period, at most 72 characters.
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

## Test doubles

| Name | Does |
|---|---|
| `…Stub` | Returns canned values |
| `…Spy` | Records calls |
| `…Fake` | Working simplified implementation, such as an in-memory file system |
| `…Mock` | Verifies expectations; only when a spy is not enough |

## Adding a module

1. Write its first test in `Tests/<Module>Tests/<Type>Tests.swift`.
2. Add the target and its test target to `Package.swift`.
3. Add `Sources/<Module> <percent>` to `scripts/coverage-thresholds.txt`.
