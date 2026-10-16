#!/usr/bin/env python3
"""Mach-O package checks; Brooktrout12, MIT license. No runtime simulation."""
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

