#!/usr/bin/env python3
"""Validate the actual .deb, including every embedded code-signature page hash.

This checks build/packaging integrity, not on-device UIKit or Face ID behavior.
"""
import hashlib
import io
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unpack_tar(package, option):
    data = subprocess.check_output(["dpkg-deb", option, str(package)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        result = {}
        for member in archive.getmembers():
            require(member.uid == 0 and member.gid == 0, "Non-root package owner")
            if member.isdir():
                continue
            require(member.isfile(), "Unexpected symlink or special file")
            name = member.name.removeprefix("./")
            result[name] = (archive.extractfile(member).read(), member.mode)
        return result


def c_string(data, start):
    return data[start:data.index(b"\0", start)].decode()


def verify_slice(data, subtype):
    magic, cpu, sub, kind, count, command_size, flags, _ = struct.unpack_from("<8I", data)
    require(magic == 0xFEEDFACF and cpu == 0x100000C and kind == 6, "Not an ARM64 dylib")
    require(sub == subtype, "Fat header and slice disagree")
    require(flags & 1, "Binary was linked with undefined symbols")
    cursor = 32
    signature = None
    libraries, rpaths = [], []
    for _ in range(count):
        cmd, size = struct.unpack_from("<II", data, cursor)
        require(size >= 8 and cursor + size <= 32 + command_size, "Invalid load command")
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            offset, length = struct.unpack_from("<II", data, cursor + 8)
            require(offset + length <= len(data), "Truncated code signature")
            signature = data[offset:offset + length]
        elif cmd == 0xC:  # LC_LOAD_DYLIB
            name_offset = struct.unpack_from("<I", data, cursor + 8)[0]
            libraries.append(c_string(data, cursor + name_offset))
        elif cmd == 0x8000001C:  # LC_RPATH
            name_offset = struct.unpack_from("<I", data, cursor + 8)[0]
            rpaths.append(c_string(data, cursor + name_offset))
        cursor += size
    require(cursor == 32 + command_size, "Load-command size mismatch")
    require(signature is not None, "Unsigned slice")
    require("@rpath/CydiaSubstrate.framework/CydiaSubstrate" in libraries, "Missing substrate linkage")
    require("/var/jb/Library/Frameworks" in rpaths, "Missing rootless framework rpath")
    require("/var/jb/usr/lib" in rpaths, "Missing rootless library rpath")
    require(not any("oldabi" in x.lower() for x in libraries), "Unexpected oldabi dependency")
    require(all(x.startswith(("/System/Library/", "/usr/lib/", "@rpath/")) for x in libraries),
            "Nonportable build-host linkage")

    sig_magic, sig_length, blob_count = struct.unpack_from(">III", signature)
    require(sig_magic == 0xFADE0CC0 and sig_length <= len(signature), "Invalid signature superblob")
    directories, pages = 0, 0
    for index in range(blob_count):
        _, offset = struct.unpack_from(">II", signature, 12 + index * 8)
        blob_magic, blob_length = struct.unpack_from(">II", signature, offset)
        require(offset + blob_length <= sig_length, "Invalid signature blob bounds")
        if blob_magic != 0xFADE0C02:
            continue
        cd = signature[offset:offset + blob_length]
        _, _, _, cd_flags, hash_offset, _, _, slots, code_limit = struct.unpack_from(">9I", cd)
        hash_size, hash_type, _, page_power = struct.unpack_from("4B", cd, 36)
        require(cd_flags & 2, "Missing ad-hoc signing flag")
        require(hash_type in (1, 2, 3), "Unsupported signature hash algorithm")
        require(code_limit <= len(data), "Invalid signed code limit")
        page_size = (1 << page_power) if page_power else code_limit
        require(slots == (code_limit + page_size - 1) // page_size, "Code-slot count mismatch")
        require(hash_offset + slots * hash_size <= len(cd), "Truncated code-slot hashes")
        for slot in range(slots):
            block = data[slot * page_size:min((slot + 1) * page_size, code_limit)]
            calculated = (hashlib.sha1(block) if hash_type == 1 else hashlib.sha256(block)).digest()
            expected = cd[hash_offset + slot * hash_size:hash_offset + (slot + 1) * hash_size]
            require(calculated[:hash_size] == expected, f"Code-signature mismatch in page {slot}")
        directories += 1
        pages += slots
    require(directories > 0, "Missing CodeDirectory")
    return {"architecture": "arm64e" if subtype & 0xFFFFFF == 2 else "arm64",
            "verified_code_directories": directories, "verified_page_hashes": pages,
            "libraries": libraries, "rpaths": rpaths}


def main():
    package = Path(sys.argv[1]).resolve()
    payload = unpack_tar(package, "--fsys-tarfile")
    prefix = "var/jb/Library/MobileSubstrate/DynamicLibraries/InstantPasscode18"
    require(set(payload) == {prefix + ".dylib", prefix + ".plist"}, "Unexpected package payload")
    filter_plist = plistlib.loads(payload[prefix + ".plist"][0])
    require(filter_plist == {"Filter": {"Bundles": ["com.apple.springboard"]}}, "Incorrect injection scope")
    require(payload[prefix + ".dylib"][1] == 0o755, "Incorrect dylib mode")
    control = unpack_tar(package, "--ctrl-tarfile")
    metadata = dict(line.split(": ", 1) for line in control["control"][0].decode().splitlines() if ": " in line)
    require(metadata["Architecture"] == "iphoneos-arm64", "Incorrect Debian architecture")
    require(metadata["Package"] == "com.brooktrout12.instantpasscode18", "Incorrect package ID")
    require(metadata["Depends"] == "firmware (>= 17.0), firmware (<< 19.0), mobilesubstrate", "Incorrect dependencies")
    require(control["postinst"][1] == 0o755, "Post-install script is not executable")
    subprocess.run(["sh", "-n"], input=control["postinst"][0], check=True)
    data = payload[prefix + ".dylib"][0]
    magic, count = struct.unpack_from(">II", data)
    require(magic == 0xCAFEBABE and count == 2, "Expected two Mach-O slices")
    slices = []
    for i in range(count):
        cpu, sub, offset, length, align = struct.unpack_from(">5I", data, 8 + i * 20)
        require(cpu == 0x100000C and offset % (1 << align) == 0, "Invalid fat architecture")
        require(offset + length <= len(data), "Truncated architecture slice")
        slices.append(verify_slice(data[offset:offset + length], sub))
    require({s["architecture"] for s in slices} == {"arm64", "arm64e"}, "Missing target architecture")
    print(json.dumps({"package": package.name, "version": metadata["Version"],
                      "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
                      "result": "PASS: package and code-signature integrity",
                      "device_tested": False, "slices": slices}, indent=2))


if __name__ == "__main__":
    main()
