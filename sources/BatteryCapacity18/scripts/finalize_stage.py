#!/usr/bin/env python3
"""Convert legacy arm64e objects at staging time; never alter shared Theos files."""
import argparse
from pathlib import Path
import shutil
import struct
import subprocess


def slices(data):
    if data[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", data, 4)[0]
        result = []
        for i in range(count):
            pos = 8 + i * 20
            cpu, subtype, offset, size, _align = struct.unpack_from(">IIIII", data, pos)
            result.append((cpu, subtype, offset, size, pos))
        return result
    if data[:4] == b"\xcf\xfa\xed\xfe":
        cpu, subtype = struct.unpack_from("<II", data, 4)
        return [(cpu, subtype, 0, len(data), None)]
    raise RuntimeError("Expected a 64-bit Mach-O or FAT Mach-O")


def convert(binary, identifier, converter, signer):
    before = binary.read_bytes()
    legacy = [s for s in slices(before) if s[0] == 0x0100000C
              and (s[1] & 0xFFFFFF) == 2 and not (s[1] & 0x80000000)]
    if not legacy:
        print(f"Modern ABI already present: {binary.name}")
        return
    converter = converter or shutil.which("allemande")
    signer = signer or shutil.which("ldid")
    if not converter or not signer:
        raise RuntimeError("Legacy arm64e ABI detected. Build with a modern Apple toolchain, "
                           "or pass BC18_ALLEMANDE=/path/to/allemande and BC18_LDID=/path/to/ldid.")
    result = subprocess.run([converter, str(binary)], capture_output=True, text=True, timeout=60)
    if result.returncode or "ERROR:" in result.stderr:
        raise RuntimeError(f"ABI conversion failed: {result.stderr[-2000:]}")
    data = bytearray(binary.read_bytes())
    for cpu, subtype, offset, size, fat_pos in slices(data):
        if cpu == 0x0100000C and (subtype & 0xFFFFFF) == 2:
            # allemande performs the Objective-C metadata conversion. Only AFTER
            # that conversion, advertise versioned ptrauth ABI 0 in both headers.
            if bytes(data[offset:offset + size]) == before[offset:offset + size]:
                raise RuntimeError("Converter did not modify the legacy arm64e slice")
            struct.pack_into("<I", data, offset + 8, 0x80000002)
            if fat_pos is not None:
                struct.pack_into(">I", data, fat_pos + 4, 0x80000002)
        elif bytes(data[offset:offset + size]) != before[offset:offset + size]:
            raise RuntimeError("Converter unexpectedly modified a non-arm64e slice")
    binary.write_bytes(data)
    # Converting any signed bytes invalidates the old signature.
    subprocess.run([signer, "-S", "-Cadhoc", f"-I{identifier}", str(binary)], check=True,
                   capture_output=True, timeout=60)
    print(f"Converted and signed: {binary.name}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("staging")
    parser.add_argument("--allemande", default="")
    parser.add_argument("--ldid", default="")
    args = parser.parse_args()
    # Theos adds /var/jb during internal-package, after this stage hook.
    root = Path(args.staging).resolve() / "Library"
    files = [
        (root / "MobileSubstrate/DynamicLibraries/BatteryCapacity18.dylib", "com.brooktrout12.batterycapacity18"),
        (root / "PreferenceBundles/BatteryCapacity18Prefs.bundle/BatteryCapacity18Prefs", "com.brooktrout12.batterycapacity18.prefs"),
    ]
    for path, identifier in files:
        if not path.is_file():
            raise RuntimeError(f"Missing staged binary: {path}")
        convert(path, identifier, args.allemande, args.ldid)


if __name__ == "__main__":
    main()
