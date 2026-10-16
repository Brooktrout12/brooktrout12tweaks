#!/usr/bin/env python3
"""Validate the delivered rootless archive, not a simulated iOS environment."""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import struct
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
    domain = "com.brooktrout12.cleanquickactions"
    require(fields["Package"] == domain, "Wrong package ID")
    require(fields["Name"] == "Clean Quick Actions", "Wrong package name")
    require(fields["Version"] == "1.0.1", "Wrong package version")
    require(fields["Architecture"] == "iphoneos-arm64", "Wrong package architecture")
    require(fields["Author"] == fields["Maintainer"] == "Brooktrout12", "Wrong attribution")
    require(fields["Depends"] == "firmware (>= 17.0), firmware (<< 19.0), mobilesubstrate, preferenceloader (>= 2.2.8)",
            "Unexpected dependencies")
    require(not any(key in fields for key in ("Conflicts", "Replaces", "Breaks")), "Must remain an independent package")
    control_tar = subprocess.check_output(["dpkg-deb", "--ctrl-tarfile", str(package)])
    with tarfile.open(fileobj=io.BytesIO(control_tar), mode="r:") as archive:
        require(all(member.name.removeprefix("./") in ("control", "md5sums")
                    for member in archive.getmembers() if member.isfile()), "Unexpected maintainer script")

    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    inject = "var/jb/Library/MobileSubstrate/DynamicLibraries/"
    prefs = "var/jb/Library/PreferenceLoader/Preferences/CleanQuickActions/"
    binary_path = inject + "CleanQuickActions.dylib"
    expected = {binary_path, inject + "CleanQuickActions.plist"}
    expected |= {prefs + name for name in ("Preferences.plist", "Info.plist", "icon.png", "icon@2x.png", "icon@3x.png")}
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        members = archive.getmembers()
        require(all(m.isfile() or m.isdir() for m in members), "Unexpected special file/link")
        require(all(m.uid == 0 and m.gid == 0 for m in members), "Wrong installed ownership")
        files = {m.name.removeprefix("./"): m for m in members if m.isfile()}
        require(set(files) == expected, "Unexpected/missing payload: " + repr(set(files) ^ expected))
        contents = {name: archive.extractfile(member).read() for name, member in files.items()}
    require(plistlib.loads(contents[inject + "CleanQuickActions.plist"]) ==
            {"Filter": {"Bundles": ["com.apple.springboard"]}}, "Injection must target only SpringBoard")
    registration = plistlib.loads(contents[prefs + "Preferences.plist"])
    require(registration == {"entry": {
        "cell": "PSSwitchCell", "label": "Clean Quick Actions", "icon": "icon.png",
        "defaults": domain, "key": "Enabled", "default": True,
        "PostNotification": domain + "/preferences.changed"}}, "Wrong direct switch registration")
    info = plistlib.loads(contents[prefs + "Info.plist"])
    require(info["CFBundleIdentifier"] == domain + ".resources", "Wrong resource identity")
    require(info["CFBundleShortVersionString"] == fields["Version"], "Wrong resource version")
    require(not any(key in info for key in ("CFBundleExecutable", "NSPrincipalClass")), "Unexpected Settings controller")
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        png = contents[prefs + f"icon{suffix}.png"]
        require(png[:8] == b"\x89PNG\r\n\x1a\n" and
                struct.unpack_from(">II", png, 16) == (29 * scale, 29 * scale), "Invalid icon")
    require(files[binary_path].mode & 0o111, "Missing dylib executable permissions")
    binary = contents[binary_path]
    slices = verify_binary(binary, True)
    for marker in (b"CQASeparatorState", b"SBIconView", b"_UIContextMenuUIController",
                   b"_createMenuViewIfNecessaryForMenu:", b"_UIContextMenuListView",
                   b"_UIContextMenuSeparatorView", b"_UIContextMenuReusableSeparatorView",
                   b"_UIContextMenuGradientMaskSectionSeparatorView", b"Enabled", domain.encode()):
        require(marker in binary, "Missing runtime marker: " + repr(marker))
    for marker in (b"setOverrideUserInterfaceStyle:", b"setAlpha:", b"setBackgroundColor:",
                   b"setEffect:", b"setFrame:", b"D18RootController", b"D18MenuMaterialState"):
        require(marker not in binary, "Unexpected appearance/geometry code: " + repr(marker))
    report = {
        "result": "PASS", "name": fields["Name"], "version": fields["Version"],
        "package": package.name,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "installed_files": sorted(contents), "settings_registration": registration,
        "binaries": {"CleanQuickActions": slices},
        "on_device_tested": False,
        "direct_settings_switch_verified_on_ios": False,
        "private_class_coverage_verified_on_ios_18_6": False,
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_package.py /path/to/CleanQuickActions.deb")
    main(sys.argv[1])
