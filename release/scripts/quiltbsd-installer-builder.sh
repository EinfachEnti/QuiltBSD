#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Build QuiltBSD installer images from one entrypoint:
# - memstick.img for USB installer media
# - dvd1.iso for installer ISO media

set -eu

find_make_cmd()
{
	if [ -n "${MAKE:-}" ]; then
		printf '%s\n' "$MAKE"
		return 0
	fi

	if command -v bmake >/dev/null 2>&1; then
		printf '%s\n' "bmake"
		return 0
	fi

	if command -v make >/dev/null 2>&1; then
		printf '%s\n' "make"
		return 0
	fi

	echo "No make implementation was found in PATH." >&2
	exit 1
}

usage()
{
	cat <<'EOF2'
Usage: quiltbsd-installer-builder.sh [--img-only | --iso-only | --both]
                                    [--clean] [--no-stage-packages]
                                    [--jobs N]
                                    [--release-dir DIR] [--output-dir DIR]
                                    [--make MAKE]

Build QuiltBSD installer images from a single script.

Defaults:
  --both                 Build both memstick.img and dvd1.iso.
  --clean                Run 'make clean' before building artifacts.
  --no-stage-packages    Skip the explicit pkg-stage preflight step.
  --jobs N               Pass -jN to make for faster builds.
  --release-dir DIR      Release tree to run make in (default: ../release).
  --output-dir DIR       Copy finished artifacts here after a successful build.
  --make MAKE            make program to run (default: bmake when available,
                         otherwise make).

Environment:
  TARGET, TARGET_ARCH, WITH_DVD, SRC_CONF, MAKEOBJDIRPREFIX, __MAKE_CONF, etc.
  are passed through to the underlying release make invocation.
EOF2
}

MODE=both
MAKE_CMD=$(find_make_cmd)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=
DO_CLEAN=0
STAGE_PACKAGES=1
MAKE_JOBS=

while [ $# -gt 0 ]; do
	case "$1" in
	--img-only)
		MODE=img
		;;
	--iso-only)
		MODE=iso
		;;
	--both)
		MODE=both
		;;
	--clean)
		DO_CLEAN=1
		;;
	--no-stage-packages)
		STAGE_PACKAGES=0
		;;
	--jobs)
		shift
		[ $# -gt 0 ] || {
			echo "--jobs requires a value" >&2
			exit 1
		}
		case "$1" in
		*[!0-9]*|'')
			echo "--jobs expects a positive integer" >&2
			exit 1
			;;
		esac
		MAKE_JOBS=$1
		;;
	--release-dir)
		shift
		[ $# -gt 0 ] || {
			echo "--release-dir requires a value" >&2
			exit 1
		}
		RELEASE_DIR=$1
		;;
	--output-dir)
		shift
		[ $# -gt 0 ] || {
			echo "--output-dir requires a value" >&2
			exit 1
		}
		OUTPUT_DIR=$1
		;;
	--make)
		shift
		[ $# -gt 0 ] || {
			echo "--make requires a value" >&2
			exit 1
		}
		MAKE_CMD=$1
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage >&2
		exit 1
		;;
	esac
	shift
done

[ -f "$RELEASE_DIR/Makefile" ] || {
	echo "Release Makefile not found in $RELEASE_DIR" >&2
	exit 1
}

command -v "$MAKE_CMD" >/dev/null 2>&1 || {
	echo "make command not found: $MAKE_CMD" >&2
	exit 1
}

MAKE_ARGS=
if [ -n "$MAKE_JOBS" ]; then
	MAKE_ARGS="-j$MAKE_JOBS"
fi

make_release()
{
	target=$1
	echo "==> Running: $MAKE_CMD -C $RELEASE_DIR ${MAKE_ARGS:+$MAKE_ARGS }$target"
	if [ -n "$MAKE_ARGS" ]; then
		"$MAKE_CMD" -C "$RELEASE_DIR" "$MAKE_ARGS" "$target"
	else
		"$MAKE_CMD" -C "$RELEASE_DIR" "$target"
	fi
}

copy_artifact()
{
	artifact=$1
	[ -n "$OUTPUT_DIR" ] || return 0
	mkdir -p "$OUTPUT_DIR"
	cp "$RELEASE_DIR/$artifact" "$OUTPUT_DIR/"
}

print_artifact_summary()
{
	artifact=$1
	artifact_path="$RELEASE_DIR/$artifact"
	size_bytes=$(wc -c < "$artifact_path" | tr -d ' ')
	echo "==> Ready: $artifact_path (${size_bytes} bytes)"
	if command -v sha256 >/dev/null 2>&1; then
		sha256 "$artifact_path"
		if [ -n "$OUTPUT_DIR" ]; then
			sha256 "$OUTPUT_DIR/$(basename "$artifact")"
		fi
		return
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$artifact_path"
		if [ -n "$OUTPUT_DIR" ]; then
			shasum -a 256 "$OUTPUT_DIR/$(basename "$artifact")"
		fi
		return
	fi
	echo "==> Warning: no SHA-256 tool found; checksum skipped"
}

run_build()
{
	target=$1
	artifact=$2

	make_release "$target"
	[ -f "$RELEASE_DIR/$artifact" ] || {
		echo "Expected artifact was not created: $RELEASE_DIR/$artifact" >&2
		exit 1
	}
	copy_artifact "$artifact"
	print_artifact_summary "$artifact"
}

if [ "$DO_CLEAN" -eq 1 ]; then
	make_release clean
fi

if [ "$STAGE_PACKAGES" -eq 1 ] && [ "$MODE" != img ]; then
	make_release pkg-stage
fi

case "$MODE" in
img)
	run_build memstick memstick.img
	;;
iso)
	run_build dvdrom dvd1.iso
	;;
both)
	run_build memstick memstick.img
	run_build dvdrom dvd1.iso
	;;
esac
