#!/usr/bin/env python3
"""Check the actual distributed package. This does not simulate iOS."""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tarfile
from macho import verify_binary
from signature import require


def main(package):
    package = Path(package).resolve(strict=True)
    metadata = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True)
    fields = {}
    for line in metadata.splitlines():
        if line and not line.startswith(" ") and ": " in line:
            key, value = line.split(": ", 1)
            fields[key] = value
    require(fields["Package"] == "com.brooktrout12.3dbadgeclear18", "Wrong package ID")
    require(fields["Name"] == "3D Badge Clear 18", "Wrong package name")
    require(fields["Version"] == "1.0.1", "Wrong version")
    require(fields["Architecture"] == "iphoneos-arm64", "Wrong package architecture")
    require(fields["Author"] == fields["Maintainer"] == "Brooktrout12", "Wrong attribution")
    require(fields["Depends"] == "firmware (>= 17.0), firmware (<< 19.0), mobilesubstrate", "Unexpected dependencies")
    require("Inspired by 3DBadgeClear by isklikas." in metadata, "Missing original author credit")
    require(not any(key in fields for key in ("Conflicts", "Replaces", "Breaks")), "Unexpected package replacement")
    control = subprocess.check_output(["dpkg-deb", "--ctrl-tarfile", str(package)])
    with tarfile.open(fileobj=io.BytesIO(control), mode="r:") as archive:
        require(all(m.name.removeprefix("./") in ("control", "md5sums") for m in archive.getmembers() if m.isfile()),
                "Unexpected maintainer script")
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    base = "var/jb/Library/MobileSubstrate/DynamicLibraries/BadgeClear18"
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        members = archive.getmembers()
        require(all(m.isfile() or m.isdir() for m in members), "Unexpected special file/link")
        require(all(m.uid == 0 and m.gid == 0 for m in members), "Wrong installed ownership")
        files = {m.name.removeprefix("./"): m for m in members if m.isfile()}
        require(set(files) == {base + ".dylib", base + ".plist"}, "Unexpected installed files")
        contents = {name: archive.extractfile(member).read() for name, member in files.items()}
    require(plistlib.loads(contents[base + ".plist"]) == {"Filter": {"Bundles": ["com.apple.springboard"]}},
            "Only SpringBoard may be injected")
    require(files[base + ".dylib"].mode & 0o111, "Missing executable permission")
    binary = contents[base + ".dylib"]
    slices = verify_binary(binary, True)
    for marker in (b"effectiveApplicationShortcutItems", b"shouldActivateApplicationShortcutItem:atIndex:",
                   b"SBSApplicationShortcutItem", b"SBSApplicationShortcutSystemPrivateIcon",
                   b"initWithSystemImageName:", b"app.badge", b"Clear Badge", b"setBadge:",
                   b"com.brooktrout12.3dbadgeclear18.clear-badge", b"BC18SourceBundleIdentifier"):
        require(marker in binary, "Missing implementation marker: " + repr(marker))
    # Prevent accidentally packaging appearance overrides, precolored PNGs,
    # launch operations, notification removal or permanent badge suppression.
    for marker in (b"setOverrideUserInterfaceStyle:", b"setTintColor:", b"setHidden:",
                   b"initWithImagePNGData:", b"UIImagePNGRepresentation", b"imageWithTintColor:",
                   b"setOverrideBadgeNumberOrString:", b"removeAllDeliveredNotifications",
                   b"activateShortcut:withBundleIdentifier:forIconView:"):
        require(marker not in binary, "Unexpected unrelated operation: " + repr(marker))
    report = {
        "result": "PASS", "name": fields["Name"], "version": fields["Version"],
        "package": package.name, "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "installed_files": sorted(contents), "binaries": {"BadgeClear18": slices},
        "on_device_tested": False, "badge_clearing_verified_on_ios_18_6": False,
        "automatic_icon_tint_verified_on_ios_18_6": False,
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_package.py /path/to/3DBadgeClear18.deb")
    main(sys.argv[1])
