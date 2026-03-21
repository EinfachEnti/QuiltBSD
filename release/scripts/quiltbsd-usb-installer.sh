#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Write a QuiltBSD installer image to a selected USB device.

set -eu

: ${BSDDIALOG_OK=0}
: ${BSDDIALOG_CANCEL=1}

list_usb_candidates()
{
	for disk in $(sysctl -n kern.disks 2>/dev/null); do
		case "$disk" in
		da*|msdosfs/*|md*|cd*)
			;;
		a*|ada*|nvme*|mmcsd*)
			;;
		*)
			continue
			;;
		esac
		size=$(diskinfo "/dev/$disk" 2>/dev/null | awk '{print $3}')
		[ -n "$size" ] || size="unknown-size"
		desc=$(gpart show "$disk" 2>/dev/null | awk 'NR==1 {print $4, $5, $6}')
		[ -n "$desc" ] || desc="raw disk"
		printf '%s\t%s\t%s\n' "$disk" "$size" "$desc"
	done
}

prompt_image()
{
	if [ $# -ge 1 ]; then
		IMAGE_PATH=$1
		return 0
	fi
	printf 'Path to QuiltBSD installer image (.img, .img.xz, .iso): '
	read -r IMAGE_PATH
}

prompt_target()
{
	if [ $# -ge 2 ]; then
		TARGET_DISK=$2
		return 0
	fi

	candidates=$(list_usb_candidates)
	[ -n "$candidates" ] || {
		echo "No candidate disks found."
		exit 1
	}

	if command -v bsddialog >/dev/null 2>&1; then
		exec 5>&1
		TARGET_DISK=$(printf '%s\n' "$candidates" | awk -F '\t' '{printf "\"%s\" \"%s %s\" ", $1, $2, $3}' | \
			xargs bsddialog --backtitle "QuiltBSD USB Installer" --title "Select USB Target" \
			--menu "Choose the target disk for the QuiltBSD installer image." 0 0 0 2>&1 1>&5)
		retval=$?
		exec 5>&-
		[ $retval -eq $BSDDIALOG_OK ] || exit 1
	else
		echo "Available targets:"
		printf '%s\n' "$candidates" | awk -F '\t' '{printf "- %s (%s, %s)\n", $1, $2, $3}'
		printf 'Target disk (for example da0): '
		read -r TARGET_DISK
	fi
}

write_image()
{
	case "$IMAGE_PATH" in
	*.xz)
		xzcat "$IMAGE_PATH" | dd of="/dev/$TARGET_DISK" bs=1m conv=sync status=progress
		;;
	*)
		dd if="$IMAGE_PATH" of="/dev/$TARGET_DISK" bs=1m conv=sync status=progress
		;;
	esac
	sync
}

main()
{
	prompt_image "$@"
	[ -f "$IMAGE_PATH" ] || {
		echo "Image not found: $IMAGE_PATH"
		exit 1
	}
	prompt_target "$@"

	echo "About to erase /dev/$TARGET_DISK and write $IMAGE_PATH"
	printf 'Continue? [y/N]: '
	read -r confirm
	case "$confirm" in
	[Yy]|[Yy][Ee][Ss])
		write_image
		;;
	*)
		echo "Cancelled."
		exit 1
		;;
	esac

	echo "QuiltBSD installer image written to /dev/$TARGET_DISK"
}

main "$@"
