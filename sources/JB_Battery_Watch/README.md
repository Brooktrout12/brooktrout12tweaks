# JB Battery Watch 2.1.1 — Settings crash fix

Experimental rootless package for the user's iPhone SE (2020), iOS 17.6.1
(build 21G93), Dopamine rootless. The preference pane and package are 2.1.1;
the recorder is deliberately byte-for-byte identical to 2.1.0. Its report header
therefore still says 2.1.0. This is expected, not evidence of an incomplete upgrade.

## Install and check

1. Close Settings completely from the app switcher.
2. Install this DEB over 2.1.0 through your existing package installer.
   Do not uninstall first. Keep the same dependencies: PreferenceLoader and
   libSandy >= 1.1. Do not force installation through dependency failures.
3. Open Settings > JB Battery Watch and check the Build row says 2.1.1 rootless.
   Opening the pane requests a live check; Check Now can request another.
4. Once recording is confirmed, close Settings for the standby test.
5. Use Export Full Report to open the share sheet and save/share the single text
   report. A partial log and available error diagnostics can be exported too.

The upgrade is designed to preserve the active report and saved session deadline.
It briefly stops/restarts only this recorder through the existing maintainer
scripts. It does not start a new 24-hour session or erase completed recordings.
A completed session remains complete. Removing the package stops its recorder;
reports are retained. No other tweak is disabled or modified.

## What was wrong

The supplied Preferences crash report identifies NSInvalidArgumentException:
`-[(dynamic class) tableView]: unrecognized selector sent to instance`.
The exception stack points directly into the 2.1.0 preference bundle's redraw,
refresh, check, and appeared functions. The arm64e bundle UUID in that report
matches the actual 2.1.0 DEB. This is a bug in our pane, not evidence that another
tweak caused the Settings crash or the original battery drain.

The revised pane never sends the unsupported tableView getter. It first checks
and uses the list controller's reloadSpecifiers method. Checked fallback paths
accept only a UITableView obtained via table or the public viewIfLoaded method.
Missing methods, nil results, and wrong object types are not messaged blindly.
The local specifier cache is invalidated before a full refresh and rebuilt with
the current health/export header. A reentrancy guard prevents nested redraws.
If no supported redraw route is found, the pane shows a compatibility alert and
records the refresh route separately from recorder-health results.

## What a successful check does and does not establish

The existing check sends a unique request nonce to the recorder. The pane only
confirms a live check when the corresponding new sample and saved state appear.
Unavailable counters, access failures, malformed status, and no response remain
separate outcomes. COMPLETE means the observation window ended; it does not
require a running recorder. Export includes the pane version and refresh route.

This is a passive process/counter diagnostic, not an exact per-tweak energy meter.
Injected tweaks can share a process, so one targeted disable/re-enable test may
still be needed. Installed package versions, executable paths and process names
are included in exports. Review the file before sharing. Nothing is uploaded by
the package itself.

## Validation boundary

This release was compiled, inspected and tested on the build host. The actual
production refresh helper was tested using a host-only dispatch shim that
reproduces the old missing-selector failure. This is NOT Apple's Objective-C
runtime, UIKit, the Settings app, or an iPhone test. The fixed release has not been
run on a physical iPhone. The prior tests did not cover this runtime-selector
failure; passing simulated checks never guaranteed that the pane would open.
Real-device Settings rendering, share-sheet behavior, notification delivery,
private counter access and power overhead still require device verification.

See AUDIT.md, BUILD_NOTES.md and validation/ for scope and reproducible checks.
