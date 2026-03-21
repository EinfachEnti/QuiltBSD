QuiltBSD Source:
---------------
This is the top level of the QuiltBSD source directory.

QuiltBSD is an operating system used to power modern servers, desktops, and embedded platforms.
A large community has continually developed it for more than thirty years.
Its advanced networking, security, and storage features make QuiltBSD a strong platform for modern systems, including developer workstations and network-connected machines.

For copyright information, please see [the file COPYRIGHT](COPYRIGHT) in this directory.
Additional copyright information also exists for some sources in this tree - please see the specific source directories for more information.

The Makefile in this directory supports a number of targets for building components (or all) of the QuiltBSD source tree.
See build(7), config(8), and the system documentation for more information, including setting make(1) variables.

For information on supported CPU architectures and platforms, review the platform support documentation that accompanies this tree.

For official QuiltBSD bootable images, use the release artifacts produced from this source tree.

Source Roadmap:
---------------
| Directory | Description |
| --------- | ----------- |
| bin | System/user commands. |
| cddl | Various commands and libraries under the Common Development and Distribution License. |
| contrib | Packages contributed by 3rd parties. |
| crypto | Cryptography stuff (see [crypto/README](crypto/README)). |
| etc | Template files for /etc. |
| gnu | Commands and libraries under the GNU General Public License (GPL) or Lesser General Public License (LGPL). Please see [gnu/COPYING](gnu/COPYING) and [gnu/COPYING.LIB](gnu/COPYING.LIB) for more information. |
| include | System include files. |
| kerberos5 | Kerberos5 (Heimdal) package. |
| lib | System libraries. |
| libexec | System daemons. |
| release | Release building Makefile & associated tools. |
| rescue | Build system for statically linked /rescue utilities. |
| sbin | System commands. |
| secure | Cryptographic libraries and commands. |
| share | Shared resources. |
| stand | Boot loader sources. |
| sys | Kernel sources (see [sys/README.md](sys/README.md)). |
| targets | Support for experimental `DIRDEPS_BUILD` |
| tests | Regression tests which can be run by Kyua.  See [tests/README](tests/README) for additional information. |
| tools | Utilities for regression testing and miscellaneous tasks. |
| usr.bin | User commands. |
| usr.sbin | System administration commands. |

For information on synchronizing your source tree with QuiltBSD development branches, follow your project workflow and release engineering documentation.

QuiltBSD Tooling Guide:
-----------------------

### Write installer images to USB

From the repository root, you can use the cross-platform USB writer:

```sh
./quiltbsd-usb-installer.py /path/to/QuiltBSD-installer.img.xz
```

If you want a simple shell entrypoint, you can also run:

```sh
./usb-installer-installer.sh /path/to/QuiltBSD-installer.img.xz
```

The script detects removable targets on Linux, macOS, FreeBSD, and Windows-style environments, prompts for the destination device, and writes `.img`, `.iso`, or `.xz`-compressed installer images.

A FreeBSD-specific helper also exists in `release/scripts/quiltbsd-usb-installer.sh` for release engineering workflows.

### Build installer images

If you want one command that builds both installer formats from the release tree, use:

```sh
./release/scripts/quiltbsd-installer-builder.sh --both
```

This wrapper builds:

- `memstick.img` for USB installer media
- `dvd1.iso` for installer ISO media

You can also limit it to one format with `--img-only` or `--iso-only`, force a clean rebuild with `--clean`, control parallelism with `--jobs N`, skip the package preflight with `--no-stage-packages`, and copy finished artifacts to another directory with `--output-dir /path/to/out`.

### Use the desktop installer profile

Inside the installer, open the final configuration menu and select **Desktop Environment**.
From there you can choose one of these QuiltBSD desktop profiles:

- KDE Plasma
- GNOME
- MATE
- XFCE

The desktop installer profile adds common desktop packages such as Firefox, KDE Plasma/GNOME/MATE/XFCE options, sudo, bash, vim, tmux, rsync, zip/unzip, a QuiltBSD wallpaper, a first-network package refresh, QuiltBSD PKG GUI, and desktop launchers.

### QuiltBSD PKG GUI

The desktop profile installs a custom graphical package manager frontend named **QuiltBSD PKG GUI**.
It is available from the desktop application menu, and can also be started manually with:

```sh
/usr/local/bin/quiltbsd-pkg-gui
```

It provides GUI actions for common `pkg` operations such as install, remove, search, info, update, upgrade, clean, audit, and an advanced free-form command mode.

### QuiltBlaster 3D

The desktop profile also installs a local browser-based game named **QuiltBlaster 3D**.
You can launch it from the desktop menu or run:

```sh
/usr/local/bin/quiltblaster
```

This opens the local game in Firefox from the QuiltBSD shared data directory. The current version includes wave escalation, boss rounds every third wave, pickups, streak scoring, armor, pause support, and an improved HUD/minimap presentation.

Tips:

- Clear waves quickly to keep your streak bonus alive.
- Boss kills can drop extra healing pickups.
- Reload before pushing into tight corridors, because close-range enemies hit hard.

### First-boot maintenance helper

Desktop installs also include a manual maintenance helper:

```sh
/usr/local/bin/quiltbsd-postinstall
```

This runs `pkg update -f`, `pkg upgrade -f -y`, and cleanup actions manually after installation. In addition, the desktop profile schedules a one-shot first-network package refresh automatically on first boot.
