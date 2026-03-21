#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Ubuntu-oriented wrapper around the QuiltBSD installer builder.
# This script focuses on making Linux/Ubuntu usage explicit and safer by:
# - checking for Ubuntu/Debian style hosts
# - listing/installing required packages
# - defaulting to an Ubuntu-friendlier installer profile
# - disabling FreeBSD-specific package staging unless explicitly requested

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
RELEASE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BASE_BUILDER="$SCRIPT_DIR/quiltbsd-installer-builder.sh"

APT_PACKAGES="bmake build-essential clang llvm lld python3 git xz-utils flex bison bc rsync libelf-dev libssl-dev libarchive-tools"
MODE=both
PROFILE=online
INSTALL_DEPS=0
CHECK_ONLY=0
RUN_BUILD=1
STAGE_PACKAGES=0
FORWARD_ARGS=

usage()
{
	cat <<'EOF2'
Usage: quiltbsd-ubuntu-builder.sh [--install-deps] [--check-only]
                                  [--img-only | --iso-only | --both]
                                  [--profile online | minimal | offline]
                                  [--with-stage-packages]
                                  [-- <extra builder args>]

Ubuntu-oriented QuiltBSD installer builder wrapper.

Defaults on Ubuntu:
  --both                 Build both installer formats.
  --profile online       Prefer Ubuntu-friendlier network installer media.
  --check-only           Validate host dependencies and print next steps.
  --install-deps         Install Ubuntu/Debian package prerequisites with apt.
  --with-stage-packages  Enable pkg-stage; mainly useful inside FreeBSD,
                         not on a plain Ubuntu host.

Notes:
  * This wrapper defaults to --no-stage-packages because QuiltBSD's full
    offline package staging expects FreeBSD-specific tooling.
  * Extra args after '--' are passed through to quiltbsd-installer-builder.sh.
EOF2
}

append_forward_arg()
{
	if [ -z "$FORWARD_ARGS" ]; then
		FORWARD_ARGS=$(printf "%s" "$1")
	else
		FORWARD_ARGS=$(printf "%s\n%s" "$FORWARD_ARGS" "$1")
	fi
}

have_cmd()
{
	command -v "$1" >/dev/null 2>&1
}

load_os_release()
{
	OS_ID=unknown
	OS_VERSION_ID=
	OS_PRETTY_NAME=unknown
	if [ -f /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		OS_ID=${ID:-unknown}
		OS_VERSION_ID=${VERSION_ID:-}
		OS_PRETTY_NAME=${PRETTY_NAME:-unknown}
	fi
}

is_ubuntu_like()
{
	case "$OS_ID" in
	ubuntu|debian|linuxmint|pop|neon)
		return 0
		;;
	esac
	case " ${ID_LIKE:-} " in
	*" debian "*)
		return 0
		;;
	esac
	return 1
}

print_apt_install_command()
{
	printf 'sudo apt update && sudo apt install -y %s\n' "$APT_PACKAGES"
}

install_deps()
{
	if ! have_cmd apt-get; then
		echo "apt-get was not found; cannot install Ubuntu dependencies automatically." >&2
		exit 1
	fi
	echo "==> Installing Ubuntu build dependencies"
	apt-get update
	# shellcheck disable=SC2086
	apt-get install -y $APT_PACKAGES
}

check_dependencies()
{
	missing=
	for cmd in bmake cc clang ld.lld python3 git xz; do
		if ! have_cmd "$cmd"; then
			missing="$missing $cmd"
		fi
	done

	if [ -n "$missing" ]; then
		echo "==> Missing Ubuntu builder dependencies:$missing"
		echo "==> Install them with:"
		print_apt_install_command
		return 1
	fi

	echo "==> Core Ubuntu build tools detected"
	return 0
}

print_environment_notes()
{
	cat <<EOF2
==> Host: $OS_PRETTY_NAME
==> Release tree: $RELEASE_DIR
==> Base builder: $BASE_BUILDER
==> Default profile: $PROFILE
==> Package staging: $( [ "$STAGE_PACKAGES" -eq 1 ] && echo enabled || echo disabled )

Ubuntu notes:
- 'online' is the safest default on Ubuntu because it avoids the most FreeBSD-specific installer media path.
- 'offline' may require FreeBSD pkg/ports tooling for full package staging.
- You still need a prepared QuiltBSD source/build tree for successful release media generation.
EOF2
}

run_builder()
{
	set -- --make bmake
	case "$MODE" in
	img) set -- "$@" --img-only ;;
	iso) set -- "$@" --iso-only ;;
	both) set -- "$@" --both ;;
	esac
	set -- "$@" --profile "$PROFILE"
	if [ "$STAGE_PACKAGES" -eq 0 ]; then
		set -- "$@" --no-stage-packages
	fi
	if [ -n "$FORWARD_ARGS" ]; then
		OLD_IFS=$IFS
		IFS='\n'
		for arg in $FORWARD_ARGS; do
			set -- "$@" "$arg"
		done
		IFS=$OLD_IFS
	fi

	echo "==> Running Ubuntu builder edition"
	echo "==> Command: $BASE_BUILDER $*"
	exec "$BASE_BUILDER" "$@"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--install-deps)
		INSTALL_DEPS=1
		;;
	--check-only)
		CHECK_ONLY=1
		RUN_BUILD=0
		;;
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
		online|minimal|offline)
			PROFILE=$1
			;;
		*)
			echo "Unsupported Ubuntu builder profile: $1" >&2
			exit 1
			;;
		esac
		;;
	--with-stage-packages)
		STAGE_PACKAGES=1
		;;
	--)
		shift
		while [ $# -gt 0 ]; do
			append_forward_arg "$1"
			shift
		done
		break
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

[ -x "$BASE_BUILDER" ] || {
	echo "Base installer builder not found or not executable: $BASE_BUILDER" >&2
	exit 1
}

load_os_release
print_environment_notes

if ! is_ubuntu_like; then
	echo "==> Warning: this wrapper is intended for Ubuntu/Debian-style hosts." >&2
fi

if [ "$INSTALL_DEPS" -eq 1 ]; then
	install_deps
fi

check_dependencies

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "==> Dependency check completed. No build was started."
	exit 0
fi

if [ "$RUN_BUILD" -eq 1 ]; then
	run_builder
fi
