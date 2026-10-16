#!/usr/bin/env python3
"""Verify the original asset and test the C gain engine; no iOS runtime simulation."""
from pathlib import Path
import ctypes
import hashlib
import json
import math
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "layout/Library/Application Support/ClassicLockSound/lock.caf"
ORIGINAL_SHA256 = "90d02d979ff94defa18b05ca91ba8633a7eb73f28574b015af09d542d8331543"
original = RESOURCE.read_bytes()
assert original == (ROOT / "assets/lock-original.caf").read_bytes()
assert hashlib.sha256(original).hexdigest() == ORIGINAL_SHA256
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_streams", "-of", "json", str(RESOURCE)
], text=True))["streams"]
assert len(probe) == 1
assert (probe[0]["codec_name"], probe[0]["sample_rate"], probe[0]["channels"],
        probe[0]["duration_ts"]) == ("pcm_s16le", "44100", 2, 39047)
pcm = subprocess.check_output([
    "ffmpeg", "-v", "error", "-i", str(RESOURCE), "-map", "0:a:0",
    "-c:a", "pcm_s16le", "-f", "s16le", "-"
])
assert pcm == original[4096:]
samples = struct.unpack("<" + "h" * (len(pcm) // 2), pcm)

with tempfile.TemporaryDirectory() as folder:
    library = Path(folder) / "volume.so"
    subprocess.run(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
        "-fPIC", "-shared", str(ROOT / "BTVolume.c"), "-o", str(library)], check=True)
    code = ctypes.CDLL(str(library))
    code.BTScaleCAF.argtypes = (ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint)
    code.BTScaleCAF.restype = ctypes.c_bool
    code.BTVolumePercent.argtypes = (ctypes.c_double,)
    code.BTVolumePercent.restype = ctypes.c_int

    def scale(blob, percent, valid=True):
        buffer = ctypes.create_string_buffer(blob, len(blob))
        assert code.BTScaleCAF(buffer, len(blob), percent) is valid
        result = buffer.raw
        if not valid:
            assert result == blob, "Invalid input must not be partially modified"
        return result

    def expected(values, percent):
        return [int(math.copysign(math.floor(abs(s) * percent / 100 + 0.5), s)) for s in values]

    for value, want in [(-100, 0), (0, 0), (0.49, 0), (0.5, 1), (43.5, 44),
                        (99.49, 99), (99.5, 100), (100, 100), (1000, 100),
                        (float("nan"), 100), (float("inf"), 100), (-float("inf"), 100)]:
        assert code.BTVolumePercent(value) == want

    decoded_checks = []
    for percent in range(101):
        output = scale(original, percent)
        assert output[:4096] == original[:4096], "CAF header/metadata must be preserved"
        actual = struct.unpack("<" + "h" * len(samples), output[4096:])
        assert list(actual) == expected(samples, percent)
        assert all(abs(a - b * percent / 100) <= 0.500000001 for a, b in zip(actual, samples))
        if percent == 0:
            assert not any(actual)
        if percent == 100:
            assert output == original, "Maximum must be the exact original file"
        if percent in (0, 1, 44, 50, 99, 100):
            target = Path(folder) / f"volume-{percent}.caf"
            target.write_bytes(output)
            decoded = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(target),
                "-map", "0:a:0", "-c:a", "pcm_s16le", "-f", "s16le", "-"])
            assert decoded == output[4096:]
            decoded_checks.append(percent)

    # All possible signed 16-bit values, including both limits, at every level.
    boundary_samples = list(range(-32768, 32768))
    boundary_pcm = struct.pack("<" + "h" * len(boundary_samples), *boundary_samples)
    header = bytearray(original[:4096])
    struct.pack_into(">Q", header, 4084, len(boundary_pcm) + 4)
    synthetic = bytes(header) + boundary_pcm
    for percent in range(101):
        output = scale(synthetic, percent)
        actual = struct.unpack("<" + "h" * len(boundary_samples), output[4096:])
        assert list(actual) == expected(boundary_samples, percent)
        assert all(-32768 <= x <= 32767 for x in actual)

    malformed = [b"", b"caff", original[:7], original[:4095], original[:-1],
                 original + b"x", original + original[4080:], original[8:]]
    for offset, replacement in [(0, b"RIFF"), (5, b"\2"), (8, b"bad!"),
        (12, b"\xff" * 8), (20, struct.pack(">d", 48000)), (28, b"aac "),
        (32, struct.pack(">I", 3)), (36, struct.pack(">I", 2)),
        (40, struct.pack(">I", 2)), (44, struct.pack(">I", 1)),
        (48, struct.pack(">I", 24)), (4080, b"junk"), (4084, b"\xff" * 8),
        (4084, struct.pack(">Q", 3)), (4084, struct.pack(">Q", 5))]:
        bad = bytearray(original)
        bad[offset:offset + len(replacement)] = replacement
        malformed.append(bytes(bad))
    for bad in malformed:
        scale(bad, 50, False)
    scale(original, 101, False)
    assert not code.BTScaleCAF(None, len(original), 50)

print(json.dumps({
    "result": "PASS", "packaged_audio_sha256": ORIGINAL_SHA256,
    "frames": 39047, "sample_rate": 44100, "channels": 2,
    "minimum_is_silent": True, "maximum_bit_identical_to_original": True,
    "levels_checked": 101, "all_signed_16_bit_values_checked_per_level": 65536,
    "maximum_rounding_error_pcm_units": 0.5,
    "independent_ffmpeg_decode_at_percent": decoded_checks,
    "invalid_inputs_leave_buffer_unchanged": True,
    "device_runtime_tested": False
}, indent=2))
