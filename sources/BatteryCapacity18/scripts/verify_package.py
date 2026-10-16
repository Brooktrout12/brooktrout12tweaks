#!/usr/bin/env python3
"""Verify package layout, architectures, deployment versions, and signed code pages."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import subprocess
import sys
import tarfile

from finalize_stage import slices


def signature_report(data, signature_offset, signature_size):
    blob = data[signature_offset:signature_offset + signature_size]
    magic, length, count = struct.unpack_from(">III", blob)
    assert magic == 0xFADE0CC0 and length <= len(blob), "Missing signature superblob"
    reports = []
    for i in range(count):
        slot, offset = struct.unpack_from(">II", blob, 12 + i * 8)
        if slot not in (0, 0x1000, 0x1001, 0x1002, 0x1003, 0x1004):
            continue
        cd = blob[offset:]
        fields = struct.unpack_from(">9I4B", cd)
        cd_magic, cd_length, version, flags, hash_offset, ident_offset, special, pages, code_limit = fields[:9]
        hash_size, hash_type, _platform, page_log2 = fields[9:]
        assert cd_magic == 0xFADE0C02 and cd_length <= len(cd)
        assert flags & 2, "Expected an ad-hoc signature"
        assert code_limit <= signature_offset
        page_size = 1 << page_log2
        assert pages == (code_limit + page_size - 1) // page_size
        digest_fn = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256, 4: hashlib.sha384}[hash_type]
        for page in range(pages):
            start = page * page_size
            expected = digest_fn(data[start:min(start + page_size, code_limit)]).digest()[:hash_size]
            actual = cd[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
            assert actual == expected, f"Signature page {page} did not match"
        identifier = cd[ident_offset:cd.index(b"\0", ident_offset)].decode()
        assert identifier.startswith("com.brooktrout12.batterycapacity18")
        reports.append({"identifier": identifier, "hash_type": hash_type,
                        "verified_code_pages": pages, "special_slots": special,
                        "code_directory_version": hex(version)})
    assert reports, "No code directory found"
    return reports


def macho_report(binary):
    result = []
    archs = set()
    for cpu, subtype, offset, size, _fat_pos in slices(binary):
        data = binary[offset:offset + size]
        header = struct.unpack_from("<8I", data)
        assert header[0] == 0xFEEDFACF and header[1] == cpu and header[2] == subtype
        assert cpu == 0x0100000C
        arch = "arm64e" if (subtype & 0xFFFFFF) == 2 else "arm64"
        archs.add(arch)
        if arch == "arm64e":
            assert subtype == 0x80000002, "Legacy or unexpected arm64e ABI marker"
        commands = header[4]
        cursor = 32
        minimum = None
        libraries, rpaths = [], []
        signature = None
        symbol_table = None
        objc_classes, converted_classes = 0, 0
        selector_names = set()
        for _ in range(commands):
            command, command_size = struct.unpack_from("<II", data, cursor)
            assert command_size >= 8 and cursor + command_size <= len(data)
            if command == 0x32:
                platform, min_os, _sdk, _tools = struct.unpack_from("<4I", data, cursor + 8)
                assert platform == 2 and min_os >= 0x110000
                minimum = f"{min_os >> 16}.{(min_os >> 8) & 255}.{min_os & 255}"
            elif command == 0x25:
                min_os, _sdk = struct.unpack_from("<II", data, cursor + 8)
                assert min_os >= 0x110000
                minimum = f"{min_os >> 16}.{(min_os >> 8) & 255}.{min_os & 255}"
            elif command in (0xC, 0x80000018, 0x8000001F, 0x8000001C):
                str_offset = struct.unpack_from("<I", data, cursor + 8)[0]
                start = cursor + str_offset
                string = data[start:data.index(b"\0", start)].decode()
                (rpaths if command == 0x8000001C else libraries).append(string)
            elif command == 0x1D:
                signature = struct.unpack_from("<II", data, cursor + 8)
            elif command == 0x2:
                symbol_table = struct.unpack_from("<4I", data, cursor + 8)
            elif command == 0x19:
                sections = struct.unpack_from("<I", data, cursor + 64)[0]
                for i in range(sections):
                    sec = cursor + 72 + i * 80
                    name = data[sec:sec + 16].rstrip(b"\0")
                    section_size = struct.unpack_from("<Q", data, sec + 40)[0]
                    section_offset = struct.unpack_from("<I", data, sec + 48)[0]
                    if name == b"__objc_methname":
                        selector_names.update(data[section_offset:section_offset + section_size].split(b"\0"))
                    if name == b"__objc_data":
                        for pos in range(section_offset, section_offset + section_size, 40):
                            isa, superclass = struct.unpack_from("<QQ", data, pos)
                            objc_classes += 1
                            if (isa & 0x800D6AE100000000) == 0x800D6AE100000000 and \
                               (superclass & 0xC00DB5AB00000000) == 0xC00DB5AB00000000:
                                converted_classes += 1
            cursor += command_size
        assert minimum and signature
        assert symbol_table, "Missing symbol table for callback ABI verification"
        sym_offset, num_symbols, strings_offset, strings_size = symbol_table
        imports = []
        for i in range(num_symbols):
            str_index, n_type, _section, _desc, _value = struct.unpack_from("<IBBHQ", data, sym_offset + i * 16)
            if str_index and (n_type & 0xE) == 0:
                assert str_index < strings_size
                start = strings_offset + str_index
                imports.append(data[start:data.index(b"\0", start)].decode())
        block_symbols = {"NSConcreteGlobalBlock", "NSConcreteStackBlock", "NSConcreteMallocBlock",
                         "Block_copy", "Block_release", "imp_implementationWithBlock"}
        block_imports = [symbol for symbol in imports if symbol.lstrip("_") in block_symbols]
        assert not block_imports, f"Unsafe block callback ABI present: {block_imports}"
        # The user's 18.6 Battery controller does not implement tableView.
        # This tweak finds the existing table through public UIKit views instead.
        unsupported_accessors = sorted(n.decode() for n in selector_names if n in (b"tableView", b"table"))
        assert not unsupported_accessors, f"Unsupported controller table accessor present: {unsupported_accessors}"
        assert not any(p.startswith("/Library/") or p.startswith("/usr/lib/libsubstrate") for p in libraries)
        assert any(p.startswith("/var/jb/") for p in rpaths), "Missing rootless search paths"
        if arch == "arm64e":
            assert objc_classes and converted_classes == objc_classes, "Objective-C ABI metadata not converted"
        result.append({"architecture": arch, "cpu_subtype": hex(subtype), "minimum_ios": minimum,
                       "rootless_rpaths": rpaths, "dependencies": libraries,
                       "objc_classes": objc_classes, "converted_objc_classes": converted_classes,
                       "block_object_imports": block_imports,
                       "unsupported_table_accessors": unsupported_accessors,
                       "signatures": signature_report(data, *signature)})
    assert archs == {"arm64", "arm64e"}, "Missing an architecture"
    return result


def main():
    package = Path(sys.argv[1]).resolve()
    info = subprocess.check_output(["dpkg-deb", "-f", str(package)], text=True)
    control_fields = dict(line.split(": ", 1) for line in info.splitlines() if ": " in line)
    assert "Architecture: iphoneos-arm64" in info
    assert "firmware (>= 17.0)" in info and "firmware (<< 19.0)" in info
    assert "preferenceloader" in info and "oldabi" not in info
    archive = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar:
            if not member.isfile():
                assert member.isdir(), "Unexpected symlink or special file"
                continue
            name = str(PurePosixPath(member.name))
            assert name.startswith("var/jb/Library/") and ".." not in PurePosixPath(name).parts
            assert "/var/jb/var/jb/" not in "/" + name
            files[name] = tar.extractfile(member).read()
    prefix = "var/jb/Library/"
    tweak = prefix + "MobileSubstrate/DynamicLibraries/BatteryCapacity18.dylib"
    prefs = prefix + "PreferenceBundles/BatteryCapacity18Prefs.bundle/BatteryCapacity18Prefs"
    filter_path = prefix + "MobileSubstrate/DynamicLibraries/BatteryCapacity18.plist"
    preference_info = prefix + "PreferenceBundles/BatteryCapacity18Prefs.bundle/Info.plist"
    entry_path = prefix + "PreferenceLoader/Preferences/BatteryCapacity18.plist"
    icon_files = {}
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        bundle_icon = prefix + f"PreferenceBundles/BatteryCapacity18Prefs.bundle/icon{suffix}.png"
        loader_icon = prefix + f"PreferenceLoader/Preferences/BatteryCapacity18{suffix}.png"
        for name in (bundle_icon, loader_icon):
            assert name in files, f"Missing Settings icon: {name}"
            png = files[name]
            assert png[:8] == b"\x89PNG\r\n\x1a\n" and png[12:16] == b"IHDR"
            width, height = struct.unpack_from(">II", png, 16)
            assert width == height == 29 * scale, f"Wrong icon size: {name}"
            icon_files[name] = {"width": width, "height": height}
        assert files[bundle_icon] == files[loader_icon]
    assert set(files) == {tweak, prefs, filter_path, preference_info, entry_path} | set(icon_files)
    injection = plistlib.loads(files[filter_path])
    assert injection == {"Filter": {"Bundles": ["com.apple.Preferences"]}}
    preferences = plistlib.loads(files[preference_info])
    assert preferences["NSPrincipalClass"] == "BC18PrefsController"
    assert preferences["CFBundleExecutable"] == "BatteryCapacity18Prefs"
    assert preferences["CFBundleShortVersionString"] == control_fields["Version"]
    entry = plistlib.loads(files[entry_path])["entry"]
    assert entry["detail"] == "BC18PrefsController"
    assert entry["icon"] == "/" + prefix + "PreferenceBundles/BatteryCapacity18Prefs.bundle/icon.png"
    assert preferences["CFBundleIconFile"] == "icon.png"
    assert preferences["CFBundleIconFiles"] == ["icon.png", "icon@2x.png", "icon@3x.png"]
    report = {"package": package.name, "version": control_fields["Version"], "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
              "size": package.stat().st_size, "payload_files": sorted(files), "settings_icons": icon_files,
              "binaries": {"tweak": macho_report(files[tweak]), "preferences": macho_report(files[prefs])},
              "result": "PASS", "device_tested": False}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
