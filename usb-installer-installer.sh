#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Convenience wrapper that creates a QuiltBSD USB installer by delegating to
# the best available USB writer for the current host platform.

set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
PYTHON_WRITER="$SELF_DIR/quiltbsd-usb-installer.py"
FREEBSD_WRITER="$SELF_DIR/release/scripts/quiltbsd-usb-installer.sh"

run_freebsd_writer()
{
	if [ ! -x "$FREEBSD_WRITER" ]; then
		return 1
	fi
	exec "$FREEBSD_WRITER" "$@"
}

run_python_writer()
{
	if [ ! -f "$PYTHON_WRITER" ]; then
		return 1
	fi
	if command -v python3 >/dev/null 2>&1; then
		exec python3 "$PYTHON_WRITER" "$@"
	fi
	if command -v python >/dev/null 2>&1; then
		exec python "$PYTHON_WRITER" "$@"
	fi
	echo "python3 or python is required to run $PYTHON_WRITER" >&2
	exit 1
}

case "$(uname -s 2>/dev/null || echo unknown)" in
FreeBSD)
	run_freebsd_writer "$@" || run_python_writer "$@"
	;;
*)
	run_python_writer "$@" || {
		echo "No supported USB installer writer was found." >&2
		exit 1
	}
	;;
esac
