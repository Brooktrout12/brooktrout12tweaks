#!/usr/bin/env python3
"""Check the packaged payload, rootless linkage, and every signed code page.

Requires Python 3 and dpkg-deb. This does not simulate an iPhone or verify the
private methods on a live device.
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


def u32(data, offset, endian="<"):
    return struct.unpack_from(endian + "I", data, offset)[0]


def cstring(data, offset):
    return data[offset:data.index(b"\0", offset)].decode("utf-8")


def verify_signature(binary, offset, size):
    signature = binary[offset:offset + size]
    require(len(signature) == size, "Truncated signature")
    magic, length, count = struct.unpack_from(">III", signature)
    require(magic == 0xFADE0CC0 and length <= size, "Invalid signature SuperBlob")
    directories = []
    for index in range(count):
        _, blob_offset = struct.unpack_from(">II", signature, 12 + index * 8)
        if u32(signature, blob_offset, ">") != 0xFADE0C02:
            continue
        blob_length = u32(signature, blob_offset + 4, ">")
        directory = signature[blob_offset:blob_offset + blob_length]
        require(len(directory) == blob_length, "Truncated CodeDirectory")
        flags = u32(directory, 12, ">")
        hash_offset = u32(directory, 16, ">")
        slots = u32(directory, 28, ">")
        code_limit = u32(directory, 32, ">")
        hash_size, hash_type, _, page_shift = struct.unpack_from("BBBB", directory, 36)
        algorithms = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256,
                      4: hashlib.sha384}
        require(hash_type in algorithms, "Unsupported signature hash algorithm")
        require(0 < page_shift <= 20, "Invalid code page size")
        require(code_limit == offset, "Signature does not cover the entire code area")
        page_size = 1 << page_shift
        require(slots == (code_limit + page_size - 1) // page_size,
                "CodeDirectory page count mismatch")
        require(hash_offset + slots * hash_size <= len(directory),
                "Truncated code hashes")
        # ldid produces a jailbreak code signature without setting CS_ADHOC.
        # Verify its hashes rather than assuming a codesign-specific flag.
        for page in range(slots):
            start = page * page_size
            digest = algorithms[hash_type](binary[start:min(start + page_size, code_limit)]).digest()
            actual = directory[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
            require(digest[:hash_size] == actual, f"Code signature mismatch on page {page}")
        directories.append({"hash_type": hash_type, "flags": flags,
                            "verified_pages": slots})
    require(any(d["hash_type"] == 2 for d in directories), "Missing SHA-256 CodeDirectory")
    return directories


def verify_slice(binary):
    magic, cpu, subtype, filetype, count, commands_size = struct.unpack_from("<6I", binary)
    require(magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 6,
            "Expected an arm64-family Mach-O dylib")
    require(32 + commands_size <= len(binary), "Truncated load commands")
    dependencies, rpaths, signature, platform = [], [], None, None
    position = 32
    for _ in range(count):
        command, size = struct.unpack_from("<II", binary, position)
        require(size >= 8 and position + size <= 32 + commands_size,
                "Invalid load command size")
        if command == 0xC:
            dependencies.append(cstring(binary, position + u32(binary, position + 8)))
        elif command == 0x8000001C:
            rpaths.append(cstring(binary, position + u32(binary, position + 8)))
        elif command == 0x1D:
            signature = struct.unpack_from("<II", binary, position + 8)
        elif command == 0x32:
            platform = u32(binary, position + 8)
        position += size
    require(position == 32 + commands_size, "Load command count mismatch")
    require(platform == 2, "Expected the iOS device platform")
    require("@rpath/CydiaSubstrate.framework/CydiaSubstrate" in dependencies,
            "Missing rootless Substrate linkage")
    require("/var/jb/Library/Frameworks" in rpaths, "Missing rootless framework rpath")
    require("@loader_path/.jbroot/Library/Frameworks" in rpaths,
            "Missing relocated jailbreak rpath")
    require(signature is not None, "Unsigned dylib")
    return {"architecture": {0: "arm64", 2: "arm64e"}.get(subtype & 0xFFFFFF, str(subtype)),
            "signature": verify_signature(binary, *signature)}


def main(path):
    path = Path(path).resolve(strict=True)
    metadata = subprocess.check_output(["dpkg-deb", "--field", str(path)], text=True)
    require("Architecture: iphoneos-arm64" in metadata, "Wrong package architecture")
    require("Package: com.brooktrout12.faceidgrace" in metadata, "Wrong package identifier")
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(path)])
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        prefix = "var/jb/Library/MobileSubstrate/DynamicLibraries/"
        files = {m.name.removeprefix("./"): m for m in archive.getmembers() if m.isfile()}
        require(set(files) == {prefix + "FaceIDGrace.dylib", prefix + "FaceIDGrace.plist"},
                "Unexpected installed files")
        require(all(m.uid == 0 and m.gid == 0 for m in archive.getmembers()),
                "Package ownership must be root:wheel")
        require(all(m.isfile() or m.isdir() for m in archive.getmembers()),
                "Unexpected special file or symlink")
        binary = archive.extractfile(files[prefix + "FaceIDGrace.dylib"]).read()
        injection = plistlib.loads(archive.extractfile(files[prefix + "FaceIDGrace.plist"]).read())
        require(injection == {"Filter": {"Bundles": ["com.apple.Preferences"]}},
                "Injection filter must target Settings only")
    magic, count = struct.unpack_from(">II", binary)
    require(magic == 0xCAFEBABE and count == 2, "Expected a two-slice universal dylib")
    slices = []
    for index in range(count):
        _, _, offset, size, alignment = struct.unpack_from(">IIIII", binary, 8 + index * 20)
        require(offset % (1 << alignment) == 0 and offset + size <= len(binary),
                "Invalid fat slice bounds/alignment")
        slices.append(verify_slice(binary[offset:offset + size]))
    require({s["architecture"] for s in slices} == {"arm64", "arm64e"},
            "Missing device architecture")
    print(json.dumps({"result": "PASS", "package": path.name,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                      "installed_files": sorted(files), "slices": slices,
                      "on_device_tested": False}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_package.py /path/to/FaceIDGrace.deb")
    main(sys.argv[1])
