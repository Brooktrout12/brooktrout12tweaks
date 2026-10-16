"""Shared Mach-O signature checks; Brooktrout12, MIT license."""

import hashlib
import struct


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
