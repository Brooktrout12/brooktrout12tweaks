#!/usr/bin/env python3
"""Check the actual install archive; not an iOS runtime simulator."""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tarfile
import uuid
from signature import require, u32, cstring, verify_signature


def block_runtime_imports(binary, symtab):
    """Inspect undefined Mach-O symbols, not just source spelling.

    This release deliberately avoids compiler-generated Objective-C blocks:
    the old arm64e toolchain's block ISA was the recorded startup failure.
    """
    require(symtab is not None, "Missing symbol table for callback ABI check")
    offset, count, strings, string_size = symtab
    require(offset + count * 16 <= len(binary) and strings + string_size <= len(binary),
            "Truncated symbol table")
    forbidden = {"NSConcreteGlobalBlock", "NSConcreteStackBlock", "NSConcreteMallocBlock",
                 "Block_copy", "Block_release", "Block_object_assign", "Block_object_dispose",
                 "objc_retainBlock"}
    found = []
    for index in range(count):
        name_offset, kind, _, _, _ = struct.unpack_from("<IBBHQ", binary, offset + index * 16)
        if kind & 0xE0 or kind & 0x0E or not name_offset:
            continue
        require(name_offset < string_size, "Invalid symbol string index")
        name = cstring(binary, strings + name_offset)
        if name.lstrip("_") in forbidden:
            found.append(name)
    return sorted(set(found))


def verify_slice(binary, tweak):
    magic, cpu, subtype, filetype, count, commands_size = struct.unpack_from("<6I", binary)
    require(magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected arm64-family Mach-O")
    require(filetype == 6 if tweak else filetype in (6, 8), "Unexpected Mach-O file type")
    dependencies, rpaths, signature, platform, symtab = [], [], None, None, None
    image_uuid = None
    position = 32
    require(32 + commands_size <= len(binary), "Truncated commands")
    for _ in range(count):
        command, size = struct.unpack_from("<II", binary, position)
        require(size >= 8 and position + size <= 32 + commands_size, "Invalid command size")
        if command in (0xC, 0x80000018, 0x8000001F):
            dependencies.append(cstring(binary, position + u32(binary, position + 8)))
        elif command == 0x8000001C:
            rpaths.append(cstring(binary, position + u32(binary, position + 8)))
        elif command == 0x1D:
            signature = struct.unpack_from("<II", binary, position + 8)
        elif command == 0x32:
            platform = u32(binary, position + 8)
        elif command == 0x2:
            symtab = struct.unpack_from("<IIII", binary, position + 8)
        elif command == 0x1B:
            image_uuid = str(uuid.UUID(bytes=binary[position + 8:position + 24]))
        position += size
    require(position == 32 + commands_size and platform == 2, "Expected intact iOS load commands")
    forbidden = ("cephei", "hbprefs", "libswift", "/usr/lib/libsubstrate", "/library/frameworks/cydia")
    require(not any(term in dep.lower() for dep in dependencies for term in forbidden), "Forbidden dependency")
    if tweak:
        require("@rpath/CydiaSubstrate.framework/CydiaSubstrate" in dependencies, "Missing rootless hooking linkage")
        require("/var/jb/Library/Frameworks" in rpaths, "Missing rootless rpath")
        require("@loader_path/.jbroot/Library/Frameworks" in rpaths, "Missing relocated rootless rpath")
        require(not any("Preferences.framework" in dep for dep in dependencies), "Injected code must not load Preferences UI")
    else:
        require(any("Preferences.framework/Preferences" in dep for dep in dependencies), "Missing Settings framework")
        require(not any("CydiaSubstrate" in dep for dep in dependencies), "Settings bundle should not install hooks")
    require(signature is not None, "Unsigned Mach-O")
    require(image_uuid is not None, "Missing UUID for identifying same-version builds")
    blocks = block_runtime_imports(binary, symtab)
    require(not blocks, "Unsafe compiler block metadata for this build: " + repr(blocks))
    return {"architecture": {0: "arm64", 2: "arm64e"}.get(subtype & 0xFFFFFF, str(subtype)),
            "uuid": image_uuid,
            "dependencies": dependencies, "rpaths": rpaths,
            "block_runtime_imports": blocks,
            "signature": verify_signature(binary, *signature)}


def verify_binary(binary, tweak):
    require(u32(binary, 0, ">") == 0xCAFEBABE and u32(binary, 4, ">") == 2,
            "Expected universal arm64 + arm64e")
    results = []
    for index in range(2):
        _, _, offset, size, alignment = struct.unpack_from(">IIIII", binary, 8 + index * 20)
        require(alignment < 32 and offset % (1 << alignment) == 0 and offset + size <= len(binary),
                "Invalid fat slice bounds/alignment")
        results.append(verify_slice(binary[offset:offset + size], tweak))
    require({r["architecture"] for r in results} == {"arm64", "arm64e"}, "Missing architecture")
    return results


def main(package):
    package = Path(package).resolve(strict=True)
    metadata = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True)
    fields = {}
    for line in metadata.splitlines():
        if line and not line.startswith(" ") and ": " in line:
            key, value = line.split(": ", 1)
            fields[key] = value
    require(fields["Package"] == "com.brooktrout12.dawn18", "Wrong package ID")
    require(fields["Version"] == "1.0.1", "Unexpected package version")
    require(fields["Architecture"] == "iphoneos-arm64", "Wrong package architecture")
    require(fields["Author"] == fields["Maintainer"] == "Brooktrout12", "Wrong attribution")
    require("firmware (>= 17.0)" in fields["Depends"] and "firmware (<< 19.0)" in fields["Depends"], "Missing iOS 17/18 bounds")
    require("preferenceloader" in fields["Depends"] and "mobilesubstrate" in fields["Depends"], "Missing runtime dependencies")
    require("ws.hbang" not in fields["Depends"] and "cephei" not in fields["Depends"].lower(), "Unexpected Cephei dependency")
    require(fields["Conflicts"] == "com.ethanrdoesmc.dawn", "Must prevent simultaneous original Dawn installation")
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    base = "var/jb/Library/"
    inject = base + "MobileSubstrate/DynamicLibraries/"
    prefs = base + "PreferenceBundles/Dawn18Prefs.bundle/"
    expected = {inject + name + suffix for name in ("Dawn18Apps", "Dawn18SpringBoard") for suffix in (".dylib", ".plist")}
    expected |= {prefs + name for name in ("Dawn18Prefs", "Info.plist", "icon.png", "icon@2x.png", "icon@3x.png", "icon.svg")}
    entry = base + "PreferenceLoader/Preferences/Dawn18.plist"
    expected.add(entry)
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        members = archive.getmembers()
        require(all(m.isfile() or m.isdir() for m in members), "Unexpected link or special file")
        require(all(m.uid == 0 and m.gid == 0 for m in members), "Wrong installed ownership")
        files = {m.name.removeprefix("./"): m for m in members if m.isfile()}
        require(set(files) == expected, "Unexpected or missing payload: " + repr(set(files) ^ expected))
        contents = {name: archive.extractfile(member).read() for name, member in files.items()}
    for name, bundle in (("Dawn18Apps", "com.apple.UIKit"), ("Dawn18SpringBoard", "com.apple.springboard")):
        require(plistlib.loads(contents[inject + name + ".plist"]) == {"Filter": {"Bundles": [bundle]}}, "Wrong injection filter")
    info = plistlib.loads(contents[prefs + "Info.plist"])
    require(info["CFBundleExecutable"] == "Dawn18Prefs" and info["NSPrincipalClass"] == "D18RootController", "Wrong preference bundle entry point")
    require(info["CFBundleShortVersionString"] == fields["Version"], "Bundle version mismatch")
    require(info["CFBundleVersion"] == "2", "Bundle build version mismatch")
    registration = plistlib.loads(contents[entry])["entry"]
    require(registration["bundle"] == "Dawn18Prefs" and registration["detail"] == "D18RootController" and registration["isController"], "Wrong Settings registration")
    require(registration["label"] == "Dawn 18" and registration["icon"] == "icon.png", "Wrong Settings label/icon")
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        png = contents[prefs + f"icon{suffix}.png"]
        require(png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II", png, 16) == (29 * scale, 29 * scale), "Invalid icon")
    binaries = {}
    for name in ("Dawn18Apps", "Dawn18SpringBoard", "Dawn18Prefs"):
        path = prefs + name if name == "Dawn18Prefs" else inject + name + ".dylib"
        require(files[path].mode & 0o111, "Missing executable permissions")
        binaries[name] = verify_binary(contents[path], name != "Dawn18Prefs")
    # Public UI selectors/classes used by the registration must survive stripping.
    require(b"D18RootController" in contents[prefs + "Dawn18Prefs"], "Missing controller runtime name")
    # Build regressions only: these markers do not simulate notification display.
    springboard = contents[inject + "Dawn18SpringBoard.dylib"]
    for marker in (b"BulletinDestinationLockScreen", b"BulletinDestinationNotificationCenter",
                   b"NCExpandedPlatterViewController", b"NCExpandedPlatterView",
                   b"NCNotificationListCellActionButtonsView",
                   b"PLPlatterActionButton", b"PLPlatterActionButtonsView",
                   b"PLActionButtonsPresentingView", b"SBRingerHUDViewController",
                   b"SBRingerPillView", b"SBElasticVolumeViewController"):
        require(marker in springboard, "Missing notification revision marker: " + repr(marker))
    require(b"Ringer\x00" in contents[prefs + "Dawn18Prefs"], "Missing renamed Ringer Settings row")
    require(b"Ringer & Volume" not in contents[prefs + "Dawn18Prefs"], "Old HUD label still present")
    require(b"iOS 10 style" in contents[prefs + "Dawn18Prefs"], "Missing fourth Quick Actions option")
    for marker in (b"D18MenuMaterialState", b"_UIContextMenuListView", b"cvBackgroundView"):
        require(marker in springboard, "Missing classic menu material support: " + repr(marker))
    for path in (inject + "Dawn18Apps.dylib", prefs + "Dawn18Prefs"):
        require(b"D18MenuMaterialState" not in contents[path], "Classic menu implementation leaked outside SpringBoard")
    for name, path in (("Dawn18Apps", inject + "Dawn18Apps.dylib"),
                       ("Dawn18SpringBoard", inject + "Dawn18SpringBoard.dylib"),
                       ("Dawn18Prefs", prefs + "Dawn18Prefs")):
        require(b"RingerVolume" in contents[path], "Missing new preference key in " + name)
    for marker in (b"armExpiry", b"expirePreview:", b"expiryTimer"):
        require(marker not in springboard, "Removed expiry implementation still present")
    require(b"15 minutes" not in contents[prefs + "Dawn18Prefs"], "Removed expiry wording still present")
    report = {"result": "PASS", "version": fields["Version"], "package": package.name,
              "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
              "installed_files": sorted(contents), "binaries": binaries,
              "on_device_tested": False, "settings_visually_verified_on_ios": False,
              "private_class_coverage_verified_on_ios_18_6": False}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_package.py /path/to/Dawn18.deb")
    main(sys.argv[1])
