# Startup crash correction — package version remains 1.0.0

The supplied `SpringBoard-2026-09-14-204822.ips` records an arm64e
`EXC_BAD_ACCESS / SIGSEGV`, with a possible pointer-authentication failure,
on SpringBoard's main thread. This is a crash in Dawn 18's startup code.

The original `Dawn18SpringBoard.dylib` UUID in that report is
`02d3c91f-ac69-3fd9-9ba6-ba9844f749d4`. It matches the original build's dSYM.
Symbolicating the two tweak frames gives:

| Image offset | Original source location |
| --- | --- |
| `0x6cd0` | `D18ObserveConfiguration`, `Preferences.m:51` |
| `0x53c4` | `D18Start`, `Appearance.m:251` |

The top frame is `objc_msgSend`, with selector `retain`; the failed class pointer
corresponds to `_NSConcreteGlobalBlock`. The first tweak frame follows the retain
call at the preference-observer function's entry. Together, these identify a
failure retaining the generated callback block before its preference read or
appearance-update callback can run.

The old Linux arm64e compiler plus the existing converter did not make these
block objects compatible with the device's runtime. Inspection of the converter
shows handling for Objective-C class and constant-string metadata, but no
handling for the block metadata involved here. The previous signature checks
proved binary integrity; they did not prove compatibility of this metadata.

## Correction

- Replace the preference callback with an ordinary C function pointer and
  context. Use `dispatch_once_f`, `dispatch_async_f`, and a Darwin notification
  callback rather than compiler-generated blocks.
- Replace the lifecycle notification blocks with selector-based observers.
  The application and SpringBoard observers have distinct Objective-C names.
- Replace Settings' read/write blocks with serial selector-based operations,
  retaining background preference I/O and main-thread UI updates.
- Preserve all appearance rules, process exclusions, stored preference keys,
  UI controls/layout, package version `1.0.0`, and bundle build version `1`.

The replacement package verifier examines undefined Mach-O symbols in both
architectures of all three binaries. It rejects `_NSConcreteGlobalBlock`,
`_NSConcreteStackBlock`, and related block-runtime references. This new gate
correctly rejects the original crashing package and passes the corrected one.
Signature/code-page checks and rootless dependency/filter checks also pass.

The user subsequently confirmed that the startup-corrected build works, and
identified closed folder tiles as a remaining appearance gap. This document
records the original startup correction. The later folder/Quick Actions/preview
update retains version 1.0.0 and this binary gate; its new behavior still needs
device testing. See `README.md` and the matching `VALIDATION.json`.

## Reference

[Clang's Apple Block ABI specification](https://clang.llvm.org/docs/Block-ABI-Apple.html)
describes the block object layout and its global/stack block class references.
The crash attribution above comes from the supplied report, matched build
symbols, disassembly, and local converter source, rather than from a generic
assumption about that specification.
