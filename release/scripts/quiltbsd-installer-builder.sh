#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Build QuiltBSD installer images from one entrypoint.
# Supported installer profiles:
# - offline: full offline installer media (dvd1.iso + memstick.img)
# - online: network-oriented installer media (disc1.iso + memstick.img)
# - minimal: smallest installer media (bootonly.iso + mini-memstick.img)

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
                                    [--profile offline | online | minimal]
                                    [--clean] [--no-stage-packages]
                                    [--jobs N]
                                    [--release-dir DIR] [--output-dir DIR]
                                    [--iso-name NAME] [--img-name NAME]
                                    [--no-manifest]
                                    [--make MAKE]

Build QuiltBSD installer images from a single script.

Defaults:
  --both                 Build both ISO and USB installer artifacts.
  --profile offline      Build the full offline installer set.
  --clean                Run 'make clean' before building artifacts.
  --no-stage-packages    Skip the explicit pkg-stage preflight step.
  --jobs N               Pass -jN to make for faster builds.
  --release-dir DIR      Release tree to run make in (default: ../release).
  --output-dir DIR       Copy finished artifacts here after a successful build.
  --iso-name NAME        Rename the produced ISO in --output-dir.
  --img-name NAME        Rename the produced IMG in --output-dir.
  --no-manifest          Skip checksum/manifest generation.
  --make MAKE            make program to run (default: bmake when available,
                         otherwise make).

Profiles:
  offline                dvd1.iso + memstick.img   (recommended default)
  online                 disc1.iso + memstick.img
  minimal                bootonly.iso + mini-memstick.img

Environment:
  TARGET, TARGET_ARCH, WITH_DVD, SRC_CONF, MAKEOBJDIRPREFIX, __MAKE_CONF, etc.
  are passed through to the underlying release make invocation.
EOF2
}

MODE=both
PROFILE=offline
MAKE_CMD=$(find_make_cmd)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=
DO_CLEAN=0
STAGE_PACKAGES=1
MAKE_JOBS=
WRITE_MANIFEST=1
ISO_NAME=
IMG_NAME=

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
	--profile)
		shift
		[ $# -gt 0 ] || {
			echo "--profile requires a value" >&2
			exit 1
		}
		case "$1" in
		offline|online|minimal)
			PROFILE=$1
			;;
		*)
			echo "Unsupported profile: $1" >&2
			exit 1
			;;
		esac
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
	--iso-name)
		shift
		[ $# -gt 0 ] || {
			echo "--iso-name requires a value" >&2
			exit 1
		}
		ISO_NAME=$1
		;;
	--img-name)
		shift
		[ $# -gt 0 ] || {
			echo "--img-name requires a value" >&2
			exit 1
		}
		IMG_NAME=$1
		;;
	--no-manifest)
		WRITE_MANIFEST=0
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

iso_target_for_profile()
{
	case "$1" in
	offline)
		printf '%s\n' "dvdrom:dvd1.iso"
		;;
	online)
		printf '%s\n' "disc1.iso:disc1.iso"
		;;
	minimal)
		printf '%s\n' "bootonly.iso:bootonly.iso"
		;;
	esac
}

img_target_for_profile()
{
	case "$1" in
	offline|online)
		printf '%s\n' "memstick:memstick.img"
		;;
	minimal)
		printf '%s\n' "mini-memstick:mini-memstick.img"
		;;
	esac
}

checksum_file()
{
	artifact_path=$1
	if command -v sha256 >/dev/null 2>&1; then
		sha256 "$artifact_path"
		return 0
	fi
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$artifact_path"
		return 0
	fi
	return 1
}

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
	kind=$2
	base_name=$(basename "$artifact")
	dest_name=$base_name

	[ -n "$OUTPUT_DIR" ] || {
		printf '%s\n' "$RELEASE_DIR/$artifact"
		return 0
	}

	case "$kind" in
	iso)
		[ -n "$ISO_NAME" ] && dest_name=$ISO_NAME
		;;
	img)
		[ -n "$IMG_NAME" ] && dest_name=$IMG_NAME
		;;
	esac

	mkdir -p "$OUTPUT_DIR"
	cp "$RELEASE_DIR/$artifact" "$OUTPUT_DIR/$dest_name"
	printf '%s\n' "$OUTPUT_DIR/$dest_name"
}

print_artifact_summary()
{
	artifact_path=$1
	size_bytes=$(wc -c < "$artifact_path" | tr -d ' ')
	echo "==> Ready: $artifact_path (${size_bytes} bytes)"
	if ! checksum_file "$artifact_path"; then
		echo "==> Warning: no SHA-256 tool found; checksum skipped"
	fi
}

append_manifest_entry()
{
	artifact_path=$1
	manifest_path=$2
	size_bytes=$(wc -c < "$artifact_path" | tr -d ' ')
	{
		printf 'artifact=%s\n' "$(basename "$artifact_path")"
		printf 'path=%s\n' "$artifact_path"
		printf 'size_bytes=%s\n' "$size_bytes"
		checksum_file "$artifact_path" 2>/dev/null | sed 's/^/sha256=/' || true
		printf '\n'
	} >> "$manifest_path"
}

run_build()
{
	target=$1
	artifact=$2
	kind=$3

	make_release "$target"
	[ -f "$RELEASE_DIR/$artifact" ] || {
		echo "Expected artifact was not created: $RELEASE_DIR/$artifact" >&2
		exit 1
	}
	final_artifact=$(copy_artifact "$artifact" "$kind")
	print_artifact_summary "$final_artifact"
	BUILT_ARTIFACTS="${BUILT_ARTIFACTS}${final_artifact}\n"
}

BUILT_ARTIFACTS=

if [ "$DO_CLEAN" -eq 1 ]; then
	make_release clean
fi

ISO_SPEC=$(iso_target_for_profile "$PROFILE")
ISO_TARGET=${ISO_SPEC%%:*}
ISO_ARTIFACT=${ISO_SPEC#*:}
IMG_SPEC=$(img_target_for_profile "$PROFILE")
IMG_TARGET=${IMG_SPEC%%:*}
IMG_ARTIFACT=${IMG_SPEC#*:}

if [ "$STAGE_PACKAGES" -eq 1 ] && [ "$PROFILE" = "offline" ] && [ "$MODE" != img ]; then
	make_release pkg-stage
fi

echo "==> QuiltBSD installer profile: $PROFILE"

echo "==> ISO target: $ISO_TARGET -> $ISO_ARTIFACT"

echo "==> IMG target: $IMG_TARGET -> $IMG_ARTIFACT"

case "$MODE" in
img)
	run_build "$IMG_TARGET" "$IMG_ARTIFACT" img
	;;
iso)
	run_build "$ISO_TARGET" "$ISO_ARTIFACT" iso
	;;
both)
	run_build "$IMG_TARGET" "$IMG_ARTIFACT" img
	run_build "$ISO_TARGET" "$ISO_ARTIFACT" iso
	;;
esac

if [ "$WRITE_MANIFEST" -eq 1 ]; then
	MANIFEST_BASE=${OUTPUT_DIR:-$RELEASE_DIR}
	mkdir -p "$MANIFEST_BASE"
	MANIFEST_PATH="$MANIFEST_BASE/installer-artifacts-${PROFILE}.txt"
	: > "$MANIFEST_PATH"
	printf '%b' "$BUILT_ARTIFACTS" | while IFS= read -r artifact_path; do
		[ -n "$artifact_path" ] || continue
		append_manifest_entry "$artifact_path" "$MANIFEST_PATH"
	done
	echo "==> Wrote manifest: $MANIFEST_PATH"
fi
