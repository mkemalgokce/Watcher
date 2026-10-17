SWIFTFORMAT := .tools/swiftformat
SWIFTLINT := .tools/swiftlint
BASELINE := .swiftlint-baseline.json
ANALYZE_BASELINE := .swiftlint-analyze-baseline.json
ANALYZE_PATH := .build/analyze
# Drives the UI through the accessibility API, which needs a permission CI and fresh machines lack.
NON_UNIT_TESTS := WatcherInteractionTests

.PHONY: bootstrap tools format format-check lint lint-baseline lint-analyze lint-analyze-baseline test test-unit changelog coverage dmg

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

test:
	swift test

test-unit:
	swift test --skip '$(NON_UNIT_TESTS)'

changelog:
	git cliff -o CHANGELOG.md

# The release DMG, signed ad hoc and not notarized: make dmg VERSION=1.2.3
dmg:
	scripts/package-release.sh $(or $(VERSION),0.0.0) 1

coverage:
	scripts/coverage.sh --skip '$(NON_UNIT_TESTS)'
