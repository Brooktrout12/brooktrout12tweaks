# 2.1.1 build scope

Package/preference UI version: 2.1.1. Unchanged collector version: 2.1.0.
The collector rebuild is checked against the shipped 2.1.0 binary hash.
All inputs are included except standard build tools and real system libraries.
The dispatch regression is Linux x86_64 only and does not run Apple UI code.

Run the commands below from this source folder, then also run these before
`python assemble.py`:

```sh
clang -DJBBW_HOST_TEST -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
  -fsanitize=address,undefined -g tests/test_ui_refresh.c prefs/ui_refresh.c \
  -o build/test-ui-refresh
./build/test-ui-refresh > build/ui-refresh-test-results.txt
python tests/check_crash_fix.py
```

The archive includes complete source, tests and validation logs, not the user's
full crash report or device identifiers. The new helper is also compiled into
both real ARM64 and ARM64e preference slices.

---

# Reproducing this experimental cross-build

This package was built with the container's Clang 17 and ld64.lld 17. The container
has no Apple SDK or Xcode linker. This fix reuses the existing cross-build procedure.
No Apple SDK, proprietary framework binary, libSandy binary, or font is included.
The minimal declarations are original interface declarations, not implementations.

## Recorder

`build.py` compiles C for `arm64-apple-ios15.0`, links an ARM64 standalone PIE
executable, and emits an ad-hoc signature. A narrow libSystem text stub provides
only an explicit symbol allowlist. Private process/IOKit symbols are resolved
on-device; host tests replace that platform layer with synthetic data.

The available downstream linker rejects the input LC_BUILD_VERSION command.
The build checks the compiler's iOS target and removes only that redundant input
load command from link-temporary copies, leaving code and offsets unchanged.
The output is linked with explicit iOS 15 platform/minimum metadata.

## Preferences and ARM64e

A system preferences bundle on the target device needs special ARM64e ABI
consideration; the standalone ARM64 recorder does not solve that requirement.
`build_prefs.py` compiles separate ARM64 and actual ARM64e source objects.
The ARM64e compiler flag is `-Xclang -fptrauth-abi-version=2` and the original
object CPU subtype is checked as 0x82000002 (ARM64E with PAC ABI 2).

The pane is implemented in C using Objective-C runtime class registration and
correctly typed message calls. It has no static Objective-C class metadata.
The compiler emits ARM64e authenticated calls/returns and runtime-signed method
implementation pointers. This is not ordinary ARM64 machine code merely renamed
ARM64e to pass a loader check.

Because this LLD has no accepted ARM64e architecture mode, the following constrained
link procedure is used and explicitly remains a physical-device-test risk:

1. Reject any static Objective-C metadata sections or ARM64 authenticated-pointer
   relocations (relocation type 11) in the input objects. This build cannot handle
   such relocations and fails instead of silently ignoring them.
2. Keep all actual ARM64e instructions and supported ARM64-compatible relocations,
   but set the CPU subtype to ARM64 in temporary link input copies. Remove the
   redundant input LC_BUILD_VERSION only after checking its exact iOS target.
3. Link MH_BUNDLE with chained fixups and read-only initializer offsets, avoiding
   statically signed initializer pointers. Link only the declared interfaces:
   libSystem, libobjc, Foundation, UIKit, Preferences and @rpath/libsandy.dylib.
4. Restore the output ARM64e/PAC ABI 2 CPU subtype and rehash the ad-hoc SHA-256
   CodeDirectory pages. Verify every resulting hash and load-command bound.
5. Combine the ARM64 and ARM64e slices in a 16 KiB-aligned universal wrapper.

The absence of static authenticated pointer data is critical to this procedure.
It is not a general replacement for Apple's ARM64e linker and must not be reused
for arbitrary Objective-C/Swift binaries without a different build strategy.
Current and iOS-17-era Apple dyld source were consulted concerning supported
chained pointer formats and read-only S_INIT_FUNC_OFFSETS initializers. Static
source compatibility reasoning does not replace executing this bundle on-device.

## Commands

From this source folder, using Python 3, Clang, ld64.lld and Debian packaging tools:

```
python build.py
python build_prefs.py
python prepare_package.py
python tests/run_tests.py
clang -DJBBW_HOST_TEST -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
  -fsanitize=address,undefined -g tests/test_prefs.c prefs/health_model.c \
  prefs/export_io.c -o build/test-prefs
./build/test-prefs > build/prefs-test-results.txt
python tests/test_maintainers.py
python tests/check_binary.py
python tests/check_prefs_binary.py
python assemble.py
```

The source ZIP excludes build intermediates, Linux test executables and package
staging. Tests and the build scripts regenerate them. `assemble.py` writes the
DEB and source ZIP to `OUTPUT_DIR` (default: this source folder's parent).
The output package's files are root-owned and normal directories are mode 0755;
only the recorder and preferences executable receive mode 0755 among data files.
No setuid/setgid mode or externally downloaded binary is introduced.
