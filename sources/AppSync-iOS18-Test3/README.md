# AppSync Unified — iOS/iPadOS 18.x Test 3

**Unofficial rootless test package:** `116.0+ios18.x-test3`
**Package ID:** `ai.akemi.appsyncunified`
**Original authors:** Karen/あけみ and Linus Yang

This is the saved Test 3 DEB, published unchanged. It is a metadata-only repack
of Test 1 that permits all 18.x firmware version strings. It is not a new
upstream AppSync release or a code port, and runtime compatibility across all
18.x versions has not been established. The original lower firmware bound and
other dependency/conflict checks are retained.

Test 3 was built from Test 1, not Test 2. Only the Depends, Name, Description and
Version control fields changed. The compressed payload, executable files,
installation programs, signatures and entitlements were preserved.

## Install

Refresh the repository in Sileo or Zebra and install **AppSync Unified (iOS 18.x
Test 3)**. Perform a userspace reboot through the jailbreak app after installation.
The package version sorts after the earlier Test 1 and Test 2 versions.

## Audit and reproduction

`VERIFICATION.txt` and `verification.json` contain the original host-side audit.
`control-before.txt`, `control-after.txt`, `control.diff`, and
`extracted-manifest.json` describe the metadata change and payload checks.
No new on-device testing was performed for this repository upload.

To reproduce the exact DEB, supply the pinned Test 1 package:

```sh
python3 rebuild_from_test1.py /path/to/Test1.deb /path/to/Test3.deb
```

The required Test 1 SHA-256 is
`0dd23330c7bff2e88e45c83d31df41875a4b56c8f3f99d8417dd28991be2161c`.
The expected Test 3 SHA-256 is
`1b823bf4b832f07ac41a661296470eb55b4fb174a52c09b974caec833f0c9896`.
The repacker rejects other input bytes. `verify_package.py` additionally needs
Test 1 and the original AppSync package to repeat the historical comparison.

## Upstream source and licensing

The `upstream/` folder preserves the AppSync source repository snapshot at
commit `235aca6cddfbdc9fa87fcb5b2aec2df37ed6d65a`, whose control file declares version 116.0:
https://github.com/akemin-dayo/AppSync/tree/235aca6cddfbdc9fa87fcb5b2aec2df37ed6d65a

The original source and license notices are retained. AppSync is GPL-3.0-or-later;
see `upstream/LICENSE` and the full license in `COPYING`. Original Test 3 repack
and audit helpers in this folder are also provided under GPL-3.0-or-later.
The repository's general MIT license does not relicense AppSync.

Upstream build instructions are in `upstream/README.md`. The source snapshot is
provided separately from the byte-preserving repack method; a fresh compilation
has not been claimed to reproduce the supplied binaries byte for byte.
