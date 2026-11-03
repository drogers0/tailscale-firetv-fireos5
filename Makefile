# Thin wrapper: each target runs a script. Tunables (TS_REF, MIN_SDK, SKIP_TESTS, LINT,
# PATCH_SERIES, ...) are environment variables read by scripts/build.sh; see docs/BUILD.md.
# `make X VAR=value` and `VAR=value make X` both work.

.PHONY: check build build-emu emu-test lint clean

# Emulator ABI: arm64 on arm64 hosts (Apple Silicon), x86_64 elsewhere (CI runners).
EMU_ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)
# Emulator builds stay out of dist/, which holds the APKs that get signed and shipped.
EMU_DIST ?= $${WORKDIR:-.build}/dist-emu
LINT_DIST ?= $${WORKDIR:-.build}/dist-lint

# Tier 0: shellcheck, verify-apk tests, patch series applies to TS_REF.
check:
	shellcheck -S warning scripts/*.sh
	python3 -m unittest discover -s tests -v
	scripts/build.sh --patch-only

# Full build of the shipped armeabi-v7a APK into dist/.
build:
	scripts/build.sh

# Build for the local emulator ABI, into $(EMU_DIST).
build-emu:
	GOMOBILE_TARGET=android/$(EMU_ARCH) DIST="$(EMU_DIST)" scripts/build.sh

# Boot a fresh API 22 emulator and run the adb smoke tests against the build-emu APK.
# Usually: make build-emu emu-test
emu-test:
	EMU_ARCH=$(EMU_ARCH) DIST="$(EMU_DIST)" scripts/emu-test.sh

# Build plus Android Lint, NewApi only. The APK is a by-product, kept out of dist/.
lint:
	LINT=1 DIST="$(LINT_DIST)" scripts/build.sh

# Remove upstream checkouts and build trees; dist/ is kept.
clean:
	@case "$${WORKDIR:-.build}" in /*|*..*) echo "refusing to clean WORKDIR=$$WORKDIR" >&2; exit 1 ;; esac
	rm -rf "./$${WORKDIR:-.build}"
