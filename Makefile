SWIFTFORMAT := .tools/swiftformat
SWIFTLINT := .tools/swiftlint
BASELINE := .swiftlint-baseline.json
ANALYZE_BASELINE := .swiftlint-analyze-baseline.json
ANALYZE_PATH := .build/analyze
# A regex over Module.Suite ids; anchored so WatcherE2ETests.WatcherCLITests stays out.
UNIT_TESTS := ^(WatcherCoreTests|WatcherUITests|WatcherCLITests)\.
# Interaction tests need the Accessibility permission CI lacks, snapshots are gated per macOS and E2E runs a child
# process coverage cannot see; the gate measures unit and integration tests only.
OUTSIDE_COVERAGE := WatcherInteractionTests|WatcherSnapshotTests|WatcherE2ETests

.PHONY: bootstrap tools format format-check lint lint-baseline lint-analyze lint-analyze-baseline test test-unit \
	test-scripts test-integration test-smoke test-e2e test-snapshot snapshots-record test-interaction test-tsan changelog coverage dmg

bootstrap:
	brew bundle --no-upgrade
	$(MAKE) tools
	lefthook install

tools:
	scripts/install-tools.sh

format:
	$(SWIFTFORMAT) .

format-check:
	$(SWIFTFORMAT) --lint .

# The baseline holds the violations that predate the lint setup; only new ones fail.
lint:
	$(SWIFTLINT) lint --strict --quiet --baseline $(BASELINE)

lint-baseline:
	$(SWIFTLINT) lint --quiet --write-baseline $(BASELINE) || true

# A fresh scratch path makes swift build log every compiler invocation the analyzer needs.
.build/analyze.log:
	rm -rf $(ANALYZE_PATH) && mkdir -p .build
	swift build -v --build-tests --scratch-path $(ANALYZE_PATH) > $@ 2>&1

lint-analyze:
	rm -f .build/analyze.log && $(MAKE) .build/analyze.log
	$(SWIFTLINT) analyze --strict --quiet --baseline $(ANALYZE_BASELINE) --compiler-log-path .build/analyze.log

lint-analyze-baseline:
	rm -f .build/analyze.log && $(MAKE) .build/analyze.log
	$(SWIFTLINT) analyze --quiet --write-baseline $(ANALYZE_BASELINE) --compiler-log-path .build/analyze.log || true

# Network, process and window tests measure time, so they run one at a time, as XCTest did. Interaction tests drive
# every window of the process, so they run alone in test-interaction.
test:
	swift test --no-parallel --skip WatcherInteractionTests

test-unit:
	swift test --filter '$(UNIT_TESTS)'

# The script tests CI runs in its "Test scripts" step.
test-scripts:
	for script in scripts/tests/*-test.sh; do bash "$$script" || exit 1; done

test-integration:
	swift test --no-parallel --filter WatcherIntegrationTests

# Every smoke suite is named *SmokeTests; the binary is built first for the same reason as in test-e2e.
test-smoke:
	swift build --product watcher-cli
	WATCHER_CLI="$$(swift build --show-bin-path)/watcher-cli" swift test --filter SmokeTests

# Built first because a test cannot run swift build while swift test holds the build lock.
test-e2e:
	swift build --product watcher-cli
	WATCHER_CLI="$$(swift build --show-bin-path)/watcher-cli" swift test --filter WatcherE2ETests

test-snapshot:
	swift test --filter WatcherSnapshotTests

# Rewrites every reference for this macOS; each rewritten snapshot is reported as a failure, so the run exits non-zero.
snapshots-record:
	SNAPSHOT_TESTING_RECORD=all swift test --filter WatcherSnapshotTests

test-interaction:
	swift test --filter WatcherInteractionTests

# ThreadSanitizer over the same tests the coverage gate measures, in its own build folder.
test-tsan:
	swift test --sanitize=thread --no-parallel --scratch-path .build/tsan --skip '$(OUTSIDE_COVERAGE)'

changelog:
	git cliff -o CHANGELOG.md

# The release DMG, signed ad hoc and not notarized: make dmg VERSION=1.2.3
dmg:
	scripts/package-release.sh $(or $(VERSION),0.0.0) 1

coverage:
	scripts/coverage.sh --no-parallel --skip '$(OUTSIDE_COVERAGE)'
