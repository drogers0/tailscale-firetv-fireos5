# Thin wrapper: each target runs a script. Tunables (TS_REF, MIN_SDK, SKIP_TESTS, LINT,
# PATCH_SERIES, ...) are environment variables read by scripts/build.sh; see docs/BUILD.md.
# `make X VAR=value` and `VAR=value make X` both work.

.PHONY: check build build-emu lint clean

# Emulator ABI: arm64 on arm64 hosts (Apple Silicon), x86_64 elsewhere (CI runners).
EMU_ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)

# Tier 0: shellcheck, verify-apk tests, patch series applies to TS_REF.
check:
	shellcheck -S warning scripts/*.sh
	python3 -m unittest discover -s tests -v
	scripts/build.sh --patch-only

# Full build of the shipped armeabi-v7a APK into dist/.
build:
	scripts/build.sh

# Build for the local emulator ABI.
build-emu:
	GOMOBILE_TARGET=android/$(EMU_ARCH) scripts/build.sh

# Build plus Android Lint, NewApi only.
lint:
	LINT=1 scripts/build.sh

# Remove upstream checkouts and build trees; dist/ is kept.
clean:
	rm -rf "$${WORKDIR:-.build}"
