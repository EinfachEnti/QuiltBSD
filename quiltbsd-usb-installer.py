#!/usr/bin/env python3
"""Cross-platform QuiltBSD installer image writer.

Creates/writes a QuiltBSD installer image to a selected USB target on
Linux, macOS, FreeBSD, or Windows. Supports raw images and .xz-compressed
images.
"""

from __future__ import annotations

import argparse
import json
import lzma
import os
import platform
import plistlib
import subprocess
import sys
from pathlib import Path

CHUNK_SIZE = 1024 * 1024


def run(cmd, *, check=True, capture=True, text=True):
    return subprocess.run(cmd, check=check, capture_output=capture, text=text)


def human_size(size: int | None) -> str:
    if not size:
        return "unknown"
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def list_devices_linux():
    data = json.loads(run(["lsblk", "-J", "-o", "NAME,PATH,SIZE,MODEL,RM,TYPE,TRAN,HOTPLUG"]).stdout)
    devices = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        if not (str(dev.get("rm", 0)) == "1" or dev.get("tran") == "usb" or str(dev.get("hotplug", 0)) == "1"):
            continue
        devices.append({
            "id": dev.get("path") or f"/dev/{dev['name']}",
            "label": f"{dev.get('path') or '/dev/' + dev['name']} | {dev.get('size','?')} | {dev.get('model') or 'USB disk'}",
            "path": dev.get("path") or f"/dev/{dev['name']}",
            "size": dev.get("size"),
        })
    return devices


def list_devices_macos():
    raw = subprocess.run(["diskutil", "list", "-plist", "external", "physical"], check=True, capture_output=True)
    plist = plistlib.loads(raw.stdout)
    devices = []
    for disk in plist.get("AllDisksAndPartitions", []):
        identifier = disk.get("DeviceIdentifier")
        if not identifier:
            continue
        devices.append({
            "id": f"/dev/{identifier}",
            "label": f"/dev/{identifier} | external physical disk",
            "path": f"/dev/r{identifier}",
            "size": None,
        })
    return devices


def list_devices_freebsd():
    disks = run(["sysctl", "-n", "kern.disks"]).stdout.strip().split()
    devices = []
    for disk in disks:
        if not disk.startswith(("da", "ada", "nvme", "mmcsd")):
            continue
        try:
            size = int(run(["diskinfo", f"/dev/{disk}"]).stdout.split()[2])
        except Exception:
            size = None
        devices.append({
            "id": f"/dev/{disk}",
            "label": f"/dev/{disk} | {human_size(size)} | FreeBSD disk",
            "path": f"/dev/{disk}",
            "size": size,
        })
    return devices


def list_devices_windows():
    script = (
        "Get-CimInstance Win32_DiskDrive | "
        "Select-Object DeviceID,Model,Size,InterfaceType,MediaType | ConvertTo-Json"
    )
    out = run(["powershell", "-NoProfile", "-Command", script]).stdout.strip()
    if not out:
        return []
    data = json.loads(out)
    if isinstance(data, dict):
        data = [data]
    devices = []
    for disk in data:
        if disk.get("InterfaceType") not in ("USB", "SCSI"):
            continue
        size = int(disk["Size"]) if disk.get("Size") else None
        path = disk.get("DeviceID")
        devices.append({
            "id": path,
            "label": f"{path} | {human_size(size)} | {disk.get('Model') or 'Disk'}",
            "path": path,
            "size": size,
        })
    return devices


def list_devices():
    system = platform.system()
    if system == "Linux":
        return list_devices_linux()
    if system == "Darwin":
        return list_devices_macos()
    if system == "FreeBSD":
        return list_devices_freebsd()
    if system == "Windows":
        return list_devices_windows()
    raise SystemExit(f"Unsupported OS: {system}")


def unmount_target(target: str):
    system = platform.system()
    try:
        if system == "Linux":
            run(["umount", target], check=False)
        elif system == "Darwin":
            run(["diskutil", "unmountDisk", target], check=False)
        elif system == "FreeBSD":
            run(["umount", target], check=False)
        elif system == "Windows":
            pass
    except Exception:
        pass


def open_input(path: Path):
    if path.suffix.lower() == ".xz":
        return lzma.open(path, "rb")
    return path.open("rb")


def write_image(image_path: Path, target_path: str):
    total = image_path.stat().st_size
    written = 0
    with open_input(image_path) as src, open(target_path, "wb") as dst:
        while True:
            chunk = src.read(CHUNK_SIZE)
            if not chunk:
                break
            dst.write(chunk)
            written += len(chunk)
            progress = f"{written / max(total, 1) * 100:5.1f}%" if total else f"{written} bytes"
            print(f"\rWriting... {progress}", end="", flush=True)
        dst.flush()
        os.fsync(dst.fileno())
    print("\nDone.")


def prompt(prompt_text: str) -> str:
    return input(prompt_text).strip()


def choose_device(devices):
    print("Available USB targets:")
    for idx, dev in enumerate(devices, 1):
        print(f"  {idx}. {dev['label']}")
    while True:
        choice = prompt("Choose target number: ")
        if choice.isdigit() and 1 <= int(choice) <= len(devices):
            return devices[int(choice) - 1]
        print("Invalid selection.")


def parse_args(argv: list[str]):
    parser = argparse.ArgumentParser(description="QuiltBSD USB installer writer")
    parser.add_argument("image", nargs="?")
    parser.add_argument("device", nargs="?")
    parser.add_argument("--yes", action="store_true", dest="yes")
    parser.add_argument("--list-json", action="store_true", dest="list_json")
    return parser.parse_args(argv[1:])

def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.list_json:
        print(json.dumps(list_devices()))
        return 0
    image_arg = Path(args.image).expanduser() if args.image else Path(prompt("Path to QuiltBSD installer image (.img/.img.xz/.iso): ")).expanduser()
    if not image_arg.exists():
        print(f"Image not found: {image_arg}")
        return 1

    devices = list_devices()
    if not devices:
        print("No USB target devices found.")
        return 1

    if args.device:
        wanted = args.device
        target = next((dev for dev in devices if dev["id"] == wanted or dev["path"] == wanted), None)
        if target is None:
            print(f"Target device not found: {wanted}")
            return 1
    else:
        target = choose_device(devices)
    print(f"Selected target: {target['label']}")
    if not args.yes:
        confirm = prompt(f"Erase {target['path']} and write {image_arg}? [y/N]: ")
        if confirm.lower() not in {"y", "yes"}:
            print("Cancelled.")
            return 1

    unmount_target(target["path"])
    write_image(image_arg, target["path"])
    print(f"QuiltBSD installer image written to {target['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
