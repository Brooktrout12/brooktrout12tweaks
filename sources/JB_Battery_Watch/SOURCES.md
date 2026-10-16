# Interface references consulted

Primary references, consulted 14 October 2026. No Apple SDK or framework binary
is redistributed. Constants and narrow ABI declarations are used for linkage.

- Dopamine official repository / current README: https://github.com/opa334/Dopamine
- Theos rootless packaging and standalone arm64 distinction: https://theos.dev/docs/rootless
- Apple XNU rusage_info_v2 fields:
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/resource.h
- Apple libproc declarations and wrapper implementation:
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.h
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.c
- Apple XNU task power accounting / Mach-unit time:
  https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/kern/task.c
- Apple IOKit interface declarations:
  https://raw.githubusercontent.com/apple-oss-distributions/IOKitUser/main/IOKitLib.h
- A primary developer patch discussion correcting proc_pid_rusage Mach-time units:
  https://lists.nongnu.org/archive/html/bug-gnu-emacs/2026-09/msg00303.html
- Swift developer report showing the downstream LLD input-platform rejection:
  https://forums.swift.org/t/simplifying-linux-to-darwin-cross-compilation-by-re-enabling-ld64-lld/76674

Availability of a declaration or current upstream source is not proof that the
corresponding private interface behaves identically on the target iOS build.

## Added references for the 2.1 Settings pane

- PreferenceLoader implementation and entry format:
  https://github.com/DhinakG/PreferenceLoader
  https://raw.githubusercontent.com/DhinakG/PreferenceLoader/master/prefs.xm
- Community-maintained Preferences interface declarations:
  https://raw.githubusercontent.com/theos/headers/master/Preferences/PSListController.h
  https://raw.githubusercontent.com/theos/headers/master/Preferences/PSSpecifier.h
  https://raw.githubusercontent.com/theos/headers/master/Preferences/PSTableCell.h
- libSandy author documentation, interface, package identifier and rootless linkage:
  https://raw.githubusercontent.com/opa334/libSandy/master/README.md
  https://raw.githubusercontent.com/opa334/libSandy/master/libSandy.h
  https://raw.githubusercontent.com/opa334/libSandy/master/control
  https://raw.githubusercontent.com/opa334/libSandy/master/Makefile
- Apple UIKit sharing interface:
  https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
- Apple libnotify declarations (including state values and signal delivery):
  https://raw.githubusercontent.com/apple-oss-distributions/Libnotify/main/notify.h
- Apple dyld chained fixups and initializer-offset validation:
  https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/common/MachOAnalyzer.cpp
  https://raw.githubusercontent.com/apple-oss-distributions/dyld/dyld-1122.1/common/MachOAnalyzer.cpp

The package is not sponsored or approved by the authors of these projects.
Theos' normal advice to use an appropriate Apple ARM64e toolchain still applies;
this package's constrained experimental build is separately disclosed.


## 2.1.1 crash-fix references

Primary project/API references checked for the repair:

- Theos Preferences/PSListController.h: the list-controller reload methods and
  community-declared properties. A header declaration does NOT establish that a
  private selector exists on the user's OS; the supplied runtime crash takes
  precedence over the header's tableView declaration.
  https://raw.githubusercontent.com/theos/headers/master/Preferences/PSListController.h
- Apple NSObjectProtocol responds(to:): query whether an instance supports a
  selector before sending an optional/private message.
  https://developer.apple.com/documentation/objectivec/nsobjectprotocol/responds(to:)
- Apple UITableViewController / UITableView conceptual documentation: table
  controllers and views are distinct types; fallback views are type-checked.
  https://developer.apple.com/documentation/uikit/uitableviewcontroller

The exact fault attribution is based on the user-supplied local .ips report and
matching local DEB image UUID, not an online anecdote. No claim about current
Dopamine release availability or other installed tweaks is needed for this fix.
