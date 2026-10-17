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
    sections, minimum = [], None
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
            minimum = u32(binary, position + 12)
        elif command == 0x2:
            symtab = struct.unpack_from("<IIII", binary, position + 8)
        elif command == 0x1B:
            image_uuid = str(uuid.UUID(bytes=binary[position + 8:position + 24]))
        elif command == 0x19:
            for index in range(u32(binary, position + 64)):
                pos = position + 72 + index * 80
                name = binary[pos:pos + 16].split(b'\0', 1)[0].decode()
                length = struct.unpack_from('<Q', binary, pos + 40)[0]
                start = u32(binary, pos + 48)
                sections.append((name, start, length))
        position += size
    require(position == 32 + commands_size and platform == 2, "Expected intact iOS load commands")
    require(minimum == 0x110000, "Expected iOS 17.0 deployment minimum")
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
    classes = strings = 0
    if subtype & 0xFFFFFF == 2:
        for name, start, length in sections:
            if name == '__objc_data':
                require(length % 40 == 0, "Invalid Objective-C records")
                for pos in range(start, start + length, 40):
                    isa, superclass = struct.unpack_from('<QQ', binary, pos)
                    require(isa & 0x800D6AE100000000 == 0x800D6AE100000000,
                            "Unconverted arm64e class ISA")
                    require(superclass & 0xC00DB5AB00000000 == 0xC00DB5AB00000000,
                            "Unconverted arm64e superclass")
                    classes += 1
            elif name == '__cfstring':
                require(length % 32 == 0, "Invalid constant-string records")
                for pos in range(start, start + length, 32):
                    isa = struct.unpack_from('<Q', binary, pos)[0]
                    require(isa & 0xFFFFFFFF00000000 == 0xC0156AE100000000,
                            "Unconverted arm64e constant-string ISA")
                    strings += 1
        require(classes == 2 and strings > 0, "Missing converted runtime records")
    signatures = verify_signature(binary, *signature)
    require(all(item['flags'] & 2 for item in signatures), "Expected ad-hoc signature flag")
    return {"architecture": {0: "arm64", 2: "arm64e"}.get(subtype & 0xFFFFFF, str(subtype)),
            "uuid": image_uuid,
            "minimum_ios": "17.0", "converted_objc_records": classes,
            "converted_constant_strings": strings,
            "dependencies": dependencies, "rpaths": rpaths,
            "block_runtime_imports": blocks,
            "signature": signatures}


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

