# Changelog

## 1.0.5 — Current Discharge Rate in mA

- Adds Current Discharge Rate below Current Charge, using the existing
  five-second refresh while the battery page is visible and Settings is active.
- Reads signed `InstantAmperage` in mA, falling back to the controller's
  `Amperage` average; corresponding nested `BatteryData` fields are supported.
  Readings remain with one internal battery registry entry.
- Displays discharge as a positive mA magnitude, Charging for current flowing
  into the battery, 0 mA for a valid zero, and Unavailable for missing/invalid
  readings. Charger connection flags do not override the actual current direction.
- Decodes signed and unsigned 32/64-bit current values without loss of integer
  precision. Rejects fractional/nonfinite, nonnumeric and out-of-range readings.
  Does not estimate a rate from percentage, charge differences, or adapter data.
- Adds English/German explanation text, plus the source and signed current in
  manually copied diagnostics. Keeps the icon, warning explanation and crash fixes.

Native tests cover the current range, integer representations, charging/zero/
discharging, invalid inputs and fallback selection. Both CPU slices and code
signatures are checked. The new row has not been tested directly on an iPhone.

## 1.0.4 — Current Charge in mAh

- Adds a Current Charge row below the existing three capacity readings.
- Reads `AppleRawCurrentCapacity` in mAh, with the corresponding nested
  `BatteryData` field as a fallback. It never derives mAh from charge percentage
  or substitutes current charge for full-charge capacity.
- Accepts a genuine reported zero; missing, nonnumeric, negative, fractional,
  nonfinite and invalid sentinel values remain unavailable.
- Refreshes every five seconds while a page containing the readings is visible
  and Settings is active. The selector-based timer stops on leaving the page,
  disabling the tweak or application inactivity. All IOKit reads remain off the
  main thread, with overlapping reads coalesced. No log file is created.
- Explains full-charge capacity versus current charge in the tweak settings,
  in English and German, and adds the current-charge source to manual diagnostics.
- Preserves the warning scanner and table lookup from the user-confirmed
  working 1.0.3 build, including the original callback ABI crash fix.

Native charge-selection tests and package/signature checks cover this update;
the new row and refresh behavior have not been tested directly on an iPhone.

## 1.0.3 — Crash opening Battery settings

The supplied iOS 18.6 report records `NSInvalidArgumentException` for an
unrecognized `tableView` selector. Its BatteryCapacity18 image UUID matches
the delivered 1.0.2 arm64e binary (`674A8EC4-93AE-3AF7-BD7C-9A600492F67E`).
The return address at image offset `0x7294` follows the `page.tableView` call
at `0x7290` in `BCInspectRenderedWarnings`. The private build header declared
that accessor, but this device's controller does not implement it.

- Removes the controller table accessor entirely. Finds the existing table
  through `UIViewController.viewIfLoaded` and the public UIKit view hierarchy,
  checking table ownership and avoiding nested cell tables.
- Checks the remaining private mapping/removal methods before calling them.
  If index-path lookup is unavailable, cached cell associations provide a fallback.
- Adds a binary regression gate rejecting the unsupported `tableView`/`table`
  accessors. It rejects the exact 1.0.2 package from the report and accepts 1.0.3.
- Keeps the warning filter, Settings icon, short switch explanation, capacity
  readings and block-free callback ABI.

The reported crash is fixed in source; device UI behavior still needs testing.

## 1.0.2 — Battery message hiding and Settings icon

- Expands warning detection beyond the fixed top-level property list used in
  1.0.1, including nested strings and attributed text.
- Adds detection from rendered custom-cell and section header/footer labels.
  This covers warnings whose displayed title/body is absent from the initial
  specifier metadata, and a layout pass handles warnings inserted later.
- Removes discovered warning sections through the normal Preferences APIs on
  the next main-queue turn, outside table callbacks. Specifier transformations
  are suspended during index mapping and removal to avoid inconsistent indexes.
- Keeps other controls when a warning shares a section, and preserves the
  original rows for the existing preference-toggle reload path.
- Adds a green battery icon with 29/58/87 px resources and a rootless icon path.
- Adds a short English/German explanation below Hide Battery Message: Apple
  may show it when a battery cannot be verified, for example after replacement;
  the switch only hides it if it is present.
- Extends manual Copy Battery Details with rendered detection counts and
  specifier property-key names. No automatic or continuous logging is added.
- Retains the block-free callbacks from 1.0.1 and the raw capacity-reading logic.

Verification covers compilation, warning-policy regressions, capacity regressions,
both CPU slices, callback ABI, packaged icons and code signatures. The updated
private Settings UI path still requires testing on the user's device.

## 1.0.1 — Settings startup crash fix

The 1.0.0 crash report identifies an arm64e pointer-authentication trap in
`CF_IS_OBJC`, called by `CFRelease` during notification cleanup as Settings enters
the foreground. The failing object maps to the foreground observer's static
global block at image offset `0xc2c0` in the exact 1.0.0 binary UUID. The battery
query had not run yet.

The legacy compiler's block-object class pointers were not fully covered by the
Objective-C metadata conversion. 1.0.1 removes compiler-generated block objects
from both binaries:

- Notification observers use selectors on a retained observer object.
- Work queues and singleton initialization use `dispatch_async_f` and
  `dispatch_once_f` with C function callbacks.
- Work queue contexts use balanced bridge retains/releases.
- Runtime hooks use saved original IMPs and ordinary C replacement functions.
- Specifier lookup uses a loop, and read completion uses a selector notification.

The package verifier now rejects imports of block-object classes and block-based
IMP creation. This additional check identifies the defect in the 1.0.0 package,
while 1.0.1 passes it. The capacity-field selection and display semantics are
unchanged. Verification still cannot replace testing the update on an iPhone.

For upgrading, install 1.0.1 over 1.0.0 and fully close/reopen Settings. No reboot
or new preference configuration is required.

## 1.0.0

Initial build: hardware-reported mAh readings and optional Important Battery
Message hiding. Superseded by 1.0.1 due to its startup callback ABI defect.
