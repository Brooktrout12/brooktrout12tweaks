# Audit — 2.1.1 Settings crash fix

## Evidence from the user's supplied crash report

- Process: Preferences; model: iPhone12,8; OS: 17.6.1 (21G93).
- Exception: NSInvalidArgumentException; unrecognized `tableView` selector.
- Relevant stack: appeared -> check -> refresh -> redraw.
- The relevant loaded image is JBBatteryWatchPrefs, arm64e.
- Loaded-image UUID 4c4c44ef-5555-3144-a1d0-5b19d5bd088b matches the arm64e
  slice extracted from the supplied 2.1.0 DEB.
- At the failure, redraw was sending `tableView` without checking support.

No full crash report, device identifier, or private preboot path is redistributed
in this source package. The evidence excerpt above is sufficient for this fix.
The report identifies this Settings crash, not the original standby-drain cause.

## Scoped changes

- Removed the unconditional tableView message entirely from the preference binary.
- Added a checked reloadSpecifiers path, verified UITableView fallback paths,
  explicit unsupported-route handling, and a redraw reentrancy guard.
- Invalidate/rebuild the pane's specifier cache across full list reloads so the
  superclass cache and live status/export header are not left inconsistent.
- Show the selected UI refresh route in Diagnostic Details and exported reports.
- Bumped preference bundle/package to 2.1.1, retaining package identity and paths.
- Updated the target wording to iOS 17.6.x; supplied report is specifically 17.6.1.
- No recorder source code, binary, interval, IPC protocol, launchd configuration,
  sandbox profile, dependency, or other-tweak behavior is changed.
- Existing install/upgrade preservation logic is retained. Only package-version
  strings change in the maintainer scripts.

Unchanged recorder SHA256:
`62b8c18d3cb59e1f0a69dcd174b410369a72f3ae5a24ad20c428486784448cb9`

All original src/ file hashes are retained in tests/recorder_baseline.json and
checked against this release. Both original binaries were reproduced exactly
from the supplied 2.1.0 source before editing the pane.

## Checks actually run

- 14 production-refresh-helper tests against a Linux host dispatch model:
  the original operation fails on the absent tableView method; the fixed helper
  works using reloadSpecifiers, or safely uses/rejects the checked fallback paths.
  Includes nil, missing methods, non-table objects, missing reloadData and
  10,000 repeated refreshes. Host tests use address/undefined-behavior sanitizers.
- 20 existing recorder integration checks with synthetic counters/virtual time,
  plus core math/identity/reset tests.
- 30 existing health-status and export-I/O checks.
- 12 maintainer-script checks with fake launchctl/probe/ownership, including an
  explicit 2.1.0 upgrade preserving report/state and a completed-session marker.
- Static checks for ARM64/ARM64e package slices, minimum iOS platform, loader
  dependencies, rootless paths, matched PreferenceLoader principal class,
  sandbox-profile scope and every ad-hoc signature page.
- Crash-fix structural checks: no standalone tableView selector remains, the
  safe helper is linked in both slices, cache/reentrancy handling is present,
  diagnostics include the UI route, and the recorder bytes remain unchanged.
- Built DEB is extracted again; all payload bytes are compared with staging.

## What was NOT tested

No physical iPhone, Apple Objective-C runtime, UIKit/Preferences framework,
real share sheet, on-device launchd/sandbox/notification service, or measured
energy overhead was available. The host dispatch model is deliberately small;
it does not simulate PSListController's complete internal implementation.
The specific known unsupported message is removed, but the new build still
requires device confirmation. Do not equate these tests with a device pass.
