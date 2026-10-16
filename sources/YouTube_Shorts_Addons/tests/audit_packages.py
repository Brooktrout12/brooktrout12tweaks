#!/usr/bin/env python3
"""Inspect the deliverable bytes: architecture, dependencies, filtering, signing."""
import hashlib
import json
import plistlib
import struct
import subprocess
import tarfile
import io
from pathlib import Path

root = Path(__file__).resolve().parents[1]
reports = []
for component in ("ForegroundOnly", "NoAds"):
    name = "YTShorts" + component
    version = "1.0.1" if component == "ForegroundOnly" else "1.0.0"
    deb = root / "dist" / f"{name}_{version}_rootless.deb"
    fields = subprocess.check_output(["dpkg-deb", "-f", str(deb)], text=True)
    assert "Architecture: iphoneos-arm64" in fields
    assert f"Version: {version}" in fields
    if component == "NoAds":
        assert hashlib.sha256(deb.read_bytes()).hexdigest() == "449dbb172279798bee5d175bce1cdc5bcf05cc0c4f2967022f292918fffdacfe", "NoAds package must remain byte-identical to Test 1"
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(deb)])
    with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
        members = tar.getmembers()
        files = [m for m in members if m.isfile()]
        assert all(m.uid == 0 and m.gid == 0 for m in members)
        assert all(m.name.startswith("./var/jb/") for m in files)
        dylibs = [m for m in files if m.name.endswith(".dylib")]
        assert len(dylibs) == 1
        assert "SpringBoard" not in str([m.name for m in files])
        dylib = tar.extractfile(dylibs[0]).read()
        plist_member = next(m for m in files if m.name.endswith(f"/{name}.plist"))
        info = plistlib.loads(tar.extractfile(plist_member).read())
        assert info == {"Filter": {"Bundles": ["com.google.ios.youtube"]}}
        magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<8I", dylib)
        assert magic == 0xfeedfacf and cpu == 0x0100000c and subtype == 0
        assert filetype == 6  # MH_DYLIB
        offset = 32
        dependencies, rpaths = [], []
        signature = None
        platform_info = None
        for _ in range(ncmds):
            command, size = struct.unpack_from("<II", dylib, offset)
            assert size >= 8 and offset + size <= 32 + sizeofcmds
            if command in (0xc, 0x80000018, 0x8000001f):
                string_offset = struct.unpack_from("<I", dylib, offset + 8)[0]
                dependencies.append(dylib[offset+string_offset:offset+size].split(b"\0")[0].decode())
            elif command == 0x8000001c:
                string_offset = struct.unpack_from("<I", dylib, offset + 8)[0]
                rpaths.append(dylib[offset+string_offset:offset+size].split(b"\0")[0].decode())
            elif command == 0x1d:
                signature = struct.unpack_from("<II", dylib, offset + 8)
            elif command == 0x32:
                platform_info = struct.unpack_from("<III", dylib, offset + 8)
            elif command == 0x25:
                minimum, sdk = struct.unpack_from("<II", dylib, offset + 8)
                platform_info = (2, minimum, sdk)
            offset += size
        assert offset == 32 + sizeofcmds
        assert signature and sum(signature) <= len(dylib)
        assert struct.unpack_from(">I", dylib, signature[0])[0] == 0xfade0cc0
        # Verify every signed code page, rather than only the signature header.
        signature_offset, signature_size = signature
        blob_count = struct.unpack_from(">I", dylib, signature_offset + 8)[0]
        verified_directories = 0
        for i in range(blob_count):
            slot, relative = struct.unpack_from(">II", dylib, signature_offset + 12 + 8 * i)
            directory_offset = signature_offset + relative
            if struct.unpack_from(">I", dylib, directory_offset)[0] != 0xfade0c02:
                continue
            (_, directory_size, cdversion, cdflags, hash_offset, ident_offset,
             special_slots, code_slots, code_limit) = struct.unpack_from(">9I", dylib, directory_offset)
            hash_size, hash_type, _, page_exp = struct.unpack_from("4B", dylib, directory_offset + 36)
            assert hash_type in (1, 2) and code_limit == signature_offset
            page_size = 1 << page_exp
            assert code_slots == (code_limit + page_size - 1) // page_size
            for page in range(code_slots):
                content = dylib[page * page_size:min((page + 1) * page_size, code_limit)]
                expected = (hashlib.sha1(content) if hash_type == 1 else hashlib.sha256(content)).digest()[:hash_size]
                start = directory_offset + hash_offset + page * hash_size
                assert dylib[start:start+hash_size] == expected
            verified_directories += 1
        assert verified_directories > 0
        assert platform_info and platform_info[0] == 2
        assert platform_info[1] == 15 << 16
        assert "/var/jb/Library/Frameworks" in rpaths
        assert any("CydiaSubstrate" in dep for dep in dependencies)
        assert not any("/workspace/" in dep for dep in dependencies + rpaths)
        assert b"com.google.ios.youtube\0" in dylib
        assert b"com.google.ios.youtubemusic\0" not in dylib
        if component == "ForegroundOnly":
            for symbol in (b"_UISceneWillDeactivateNotification", b"_UISceneDidEnterBackgroundNotification", b"_UISceneDidActivateNotification"):
                assert symbol in dylib, "Scene lifecycle dependency missing"
            assert b"1.0.1 Test 2 loaded" in dylib
        reports.append({
            "package": deb.name, "bytes": deb.stat().st_size,
            "sha256": hashlib.sha256(deb.read_bytes()).hexdigest(),
            "architecture": "arm64", "minimum_ios": "15.0",
            "only_injected_bundle": "com.google.ios.youtube",
            "dependencies": dependencies, "rpaths": rpaths,
            "ad_hoc_signature_present": True,
            "signed_code_page_hashes_verified": True,
            "device_tested": False,
        })
report = {
    "build": "ForegroundOnly 1.0.1 Test 2; NoAds 1.0.0 unchanged",
    "validation": "Compilation, lifecycle state test and package/binary inspection only; no on-device validation.",
    "packages": reports,
}
(root / "dist" / "BUILD_AUDIT.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
