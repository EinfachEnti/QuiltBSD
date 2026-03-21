#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Build QuiltBSD installer images from one entrypoint:
# - memstick.img for USB installer media
# - dvd1.iso for installer ISO media

set -eu

usage()
{
	cat <<'EOF'
Usage: quiltbsd-installer-builder.sh [--img-only | --iso-only | --both]
                                    [--release-dir DIR] [--output-dir DIR]
                                    [--make MAKE]

Build QuiltBSD installer images from a single script.

Defaults:
  --both                 Build both memstick.img and dvd1.iso.
  --release-dir DIR      Release tree to run make in (default: ../release).
  --output-dir DIR       Copy finished artifacts here after a successful build.
  --make MAKE            make program to run (default: make).

Environment:
  TARGET, TARGET_ARCH, WITH_DVD, SRC_CONF, MAKEOBJDIRPREFIX, __MAKE_CONF, etc.
  are passed through to the underlying release make invocation.
EOF
}

MODE=both
MAKE_CMD=${MAKE:-make}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=

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

copy_artifact()
{
	artifact=$1
	[ -n "$OUTPUT_DIR" ] || return 0
	mkdir -p "$OUTPUT_DIR"
	cp "$RELEASE_DIR/$artifact" "$OUTPUT_DIR/"
}

run_build()
{
	target=$1
	artifact=$2

	echo "==> Building $artifact via '$MAKE_CMD -C $RELEASE_DIR $target'"
	"$MAKE_CMD" -C "$RELEASE_DIR" "$target"
	[ -f "$RELEASE_DIR/$artifact" ] || {
		echo "Expected artifact was not created: $RELEASE_DIR/$artifact" >&2
		exit 1
	}
	copy_artifact "$artifact"
	echo "==> Ready: $RELEASE_DIR/$artifact"
}

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
