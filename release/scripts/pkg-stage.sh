#!/bin/sh
#
#

set -e

unset NO_ROOT

export ASSUME_ALWAYS_YES="YES"
export PKG_DBDIR="/tmp/pkg"
export PERMISSIVE="YES"
export REPO_AUTOUPDATE="NO"
export ROOTDIR="$PWD/dvd"
export PORTSDIR="${PORTSDIR:-/usr/ports}"

_DVD_PACKAGES_CORE="
ports-mgmt/pkg
security/sudo@default
shells/bash
shells/zsh
editors/vim
editors/emacs@nox
sysutils/tmux
sysutils/screen
net/rsync
devel/git@lite
archivers/unzip
archivers/zip
misc/freebsd-doc-all
"

_DVD_PACKAGES_DESKTOPS="
x11/xorg
x11/zenity
sysutils/seatd
x11/sddm
x11/plasma6-plasma
x11/plasma6-sddm-kcm
x11/xfce4
x11/mate
x11/gnome
x11/gdm
x11-wm/sway
"

_DVD_PACKAGES_DESKTOP_APPS="
www/firefox
www/links
x11/kde-cli-tools
x11/konsole
deskutils/dolphin
"

_DVD_PACKAGES_NETWORKING="
comms/usbmuxd
net/mpd5
"

_DVD_PACKAGES_MAIN="
${_DVD_PACKAGES_CORE}
${_DVD_PACKAGES_DESKTOPS}
${_DVD_PACKAGES_DESKTOP_APPS}
${_DVD_PACKAGES_NETWORKING}
"

_DVD_PACKAGES_KMODS="
net/wifi-firmware-kmod@release
"

# If NOPORTS is set for the release, do not attempt to build pkg(8).
if [ ! -f ${PORTSDIR}/Makefile ]; then
	echo "*** ${PORTSDIR} is missing!    ***"
	echo "*** Skipping pkg-stage.sh     ***"
	echo "*** Unset NOPORTS to fix this ***"
	exit 0
fi

usage()
{
	echo "usage: $0 [-N]"
	exit 0
}

while getopts N opt; do
	case "$opt" in
	N)	NO_ROOT=1 ;;
	*)	usage ;;
	esac
done

PKG_ARGS="--rootdir ${ROOTDIR}"
if [ "$NO_ROOT" ]; then
	PKG_ARGS="$PKG_ARGS -o INSTALL_AS_USER=1"
fi
PKGCMD="/usr/sbin/pkg ${PKG_ARGS}"

if [ ! -x /usr/local/sbin/pkg ]; then
	/etc/rc.d/ldconfig restart
	/usr/bin/make -C ${PORTSDIR}/ports-mgmt/pkg install clean
fi

export PKG_ABI=$(pkg --rootdir ${ROOTDIR} config ABI)
export PKG_ALTABI=$(pkg --rootdir ${ROOTDIR} config ALTABI 2>/dev/null)
export PKG_REPODIR="packages/${PKG_ABI}"

/bin/mkdir -p ${ROOTDIR}/${PKG_REPODIR}
if [ -n "${PKG_ALTABI}" ]; then
	ln -s ${PKG_ABI} ${ROOTDIR}/packages/${PKG_ALTABI}
fi

sanitize_package_list()
{
	input_packages=$1
	output_packages=""

	for _P in ${input_packages}; do
		if [ -d "${PORTSDIR}/${_P%%@*}" ]; then
			output_packages="${output_packages} ${_P}"
		else
			echo "*** Skipping nonexistent port: ${_P%%@*}"
		fi
	done

	echo "${output_packages# }"
}

DVD_PACKAGES_MAIN=$(sanitize_package_list "${_DVD_PACKAGES_MAIN}")
DVD_PACKAGES_KMODS=$(sanitize_package_list "${_DVD_PACKAGES_KMODS}")

# Make sure the package list is not empty.
if [ -z "${DVD_PACKAGES_MAIN}${DVD_PACKAGES_KMODS}" ]; then
	echo "*** The package list is empty."
	echo "*** Something is very wrong."
	# Exit '0' so the rest of the build process continues
	# so other issues (if any) can be addressed as well.
	exit 0
fi

echo "*** Staging installer packages for QuiltBSD media"
echo "*** Desktop packages: ${DVD_PACKAGES_MAIN}"

# Print pkg(8) information to make debugging easier.
${PKGCMD} -vv
${PKGCMD} update -f
${PKGCMD} fetch -o ${PKG_REPODIR} -r release -d ${DVD_PACKAGES_MAIN}
${PKGCMD} fetch -o ${PKG_REPODIR} -r release-kmods -d ${DVD_PACKAGES_KMODS}

# Create the 'Latest/pkg.pkg' symlink so 'pkg bootstrap' works
# using the on-disc packages.
export LATEST_DIR="${ROOTDIR}/${PKG_REPODIR}/Latest"
mkdir -p ${LATEST_DIR}
ln -s ../All/$(${PKGCMD} rquery %n-%v pkg).pkg ${LATEST_DIR}/pkg.pkg

${PKGCMD} repo ${PKG_REPODIR}

if [ "$NO_ROOT" ]; then
	mtree -c -p $ROOTDIR | mtree -C -k type,mode,link,size | \
	    grep '^./packages[/ ]' >> $ROOTDIR/METALOG
fi

# Always exit '0', even if pkg(8) complains about conflicts.
exit 0
