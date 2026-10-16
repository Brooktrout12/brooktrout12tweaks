# Battery Capacity 18 — 1.0.5

Rootless iOS 18 tweak by Brooktrout12. Includes arm64 and arm64e slices.

Adds **Full Charge Capacity**, **Design Capacity**, **Capacity vs. Design**,
**Current Charge**, and **Current Discharge Rate** directly below Apple's Maximum
Capacity row in Battery Health & Charging. Charge and capacity readings use mAh;
discharge rate uses mA; the ratio uses a percentage with one decimal place.

**1.0.5 adds Current Discharge Rate in mA with automatic refresh while displayed.**
The user confirmed the previous update works; its charge reading, refresh timer,
crash fixes, warning filter, Settings icon and battery-message explanation are
retained. Install this update over the old package and fully close/reopen Settings.
See `CHANGELOG.md` for details.

## Install

1. Open `BatteryCapacity18_1.0.5_rootless.deb` with Sileo, Zebra, or Filza and install it.
   If using Filza, install PreferenceLoader through your package manager first.
2. Fully close Settings from the app switcher, then reopen it. If the package
   manager requests a respring, complete that first.
3. Open **Settings → Battery Capacity 18**. If another tweak groups preference
   panes, it may appear under **General** or a **Tweaks** section instead.
4. **Enable Tweak** defaults to on. **Hide Battery Message** defaults to off.
5. Open **Settings → Battery → Battery Health & Charging**. On some models
   the page is simply called **Battery Health**.

Changes to the two switches apply without a respring. The master switch disables
both the added readings and message hiding. Removing the package restores the
original interface after Settings is closed and reopened.

## What the readings mean

“Full Charge Capacity” is the controller's estimate of how much charge the battery
can hold **when full**. “Current Charge” is its estimate of the charge remaining
**right now**, in mAh.

“Current Discharge Rate” is the battery controller's reported current leaving the
battery, in **mA** (milliamps). A reading of 300 mA would use about 300 mAh in one
hour if that rate stayed constant. The reading changes with device activity.
The row shows **Charging** when current flows into the battery, **0 mA** for a
reported zero, and **Unavailable** if a usable current reading is absent.

The tweak reads the internal battery's I/O Registry properties. It never turns
Apple's displayed battery-health percentage into mAh and never uses an iPhone
model-to-design-capacity table. It keeps the full-charge/design pair from one
internal battery registry entry and does not multiply values by the cell count.

Full-charge source priority:

1. `NominalChargeCapacity`
2. `BatteryData.NominalChargeCapacity`
3. `AppleRawMaxCapacity`
4. `BatteryData.AppleRawMaxCapacity`

Design capacity comes from `DesignCapacity`, then `BatteryData.DesignCapacity`.
The raw maximum fallback can fluctuate with battery conditions. The source used
is included in **Copy Battery Details**. Normalized `MaxCapacity`, Apple's health
percentage, and cell Qmax values are never used to fabricate an mAh reading.

Current charge comes from `AppleRawCurrentCapacity`, with
`BatteryData.AppleRawCurrentCapacity` as a fallback. Both keys represent mAh;
normalized `CurrentCapacity` and the status-bar percentage are not used.
A valid zero displays **0 mAh**; absent or invalid readings display **Unavailable**.
Current charge is not substituted for full-charge capacity and is not clamped to
the separate full-charge estimate. All readings stay with the selected internal
battery registry entry.

Discharge-rate source priority is `InstantAmperage`, then
`BatteryData.InstantAmperage`, then `Amperage`, then `BatteryData.Amperage`.
The `Amperage` fallback is the controller's averaged current. Negative signed
current means discharge; the row displays its positive magnitude in mA.
Positive current means charging. Direction comes from the signed reading, so
being plugged in does not override a reported net discharge or zero current.
No rate is inferred from percentage changes, mAh differences, or charger ratings.

Integer current readings retain their full precision. Signed values and negative
values encoded as unsigned 32-bit or 64-bit two's-complement integers are accepted
within a broad ±50,000 mA sanity range. Boolean/string, fractional, nonfinite,
out-of-range and wrapped floating-point values are rejected. A valid zero takes
priority over fallback readings. The selected source and signed mA value are
included in **Copy Battery Details**, from the same internal battery entry as
the charge and capacity readings.

The ratio is `reported full-charge mAh ÷ reported design mAh × 100` and is not
capped at 100%. These values are controller estimates, not an independent
measurement of the cell. A replacement or reprogrammed controller can expose
incorrect or stale values; software cannot recover the cell's true physical
capacity from a dishonest controller. The design value is the controller's
reported design value, not a verified original Apple battery specification.

Missing or invalid fields show **Unavailable**, independently for each metric.
Capacity inputs reject boolean values, strings, nonfinite/fractional values,
known invalid sentinels, and out-of-range values. A failed refresh replaces the previous
snapshot so an old successful value is not displayed as a fresh successful read.

Readings refresh asynchronously when a battery page opens or Settings returns
to the foreground. A five-second selector-based timer (with one second of timing
tolerance) refreshes the readings while a page displaying them is visible and
Settings is active. It stops when you leave the page, disable the tweak, or Settings
becomes inactive, including when the phone locks. The controller may publish new
raw readings less frequently than the refresh interval. There is no launch daemon,
network access, or continuous log. The diagnostic copy button copies only selected battery readings and battery
page metadata; it excludes device and battery serial numbers.

## Message hiding and compatibility

Message hiding removes the identified Important Battery Message section from the
battery preference pages, including its Learn More row. It does not change battery
authentication, health calculations, charging, thermal limits, performance
management, parts history, or system-wide notifications.

1.0.2 reads nested specifier text and inspects the displayed labels in custom
cells and section headers/footers. If the warning is only identifiable after
rendering or is inserted asynchronously, the filter queues a removal on the
main thread after the layout callback. It uses Preferences' normal specifier
removal/replacement APIs to keep row and section indexes consistent. A warning
first discovered from displayed content may briefly appear before removal.
1.0.3 locates the table through the already-loaded UIKit view hierarchy; it never
requests the controller’s unsupported `tableView` accessor. Remaining private
lookup/removal calls are checked for availability before use.
Other controls in a shared section are preserved. The fallback runs during
battery-page layout while hiding is enabled; warning detection adds no polling
timer or log. The charge refresh described above is separate.

The option's explanation reads: “Apple may show an Important Battery Message if
it can’t verify the battery, for example after a replacement. This option only
hides that message if it is shown.” It has no effect if the message is absent.

Apple loads the battery preference bundle lazily. The tweak waits for it, then
hooks its list controllers. It detects the capacity row using identifiers and
localized labels. English and German tweak labels are provided; Apple's strings
are used to recognize translated warning messages where available. No screen
coordinates or device-specific capacity constants are used.

If Apple omits its Maximum Capacity row, the readings appear in a separate Battery
Capacity section on the Health page. On a battery list controller with no Health
link, this section appears on the main Battery page instead.

**Build and static checks were performed; device testing was not available.**
The intended target is jailbroken iOS 18.x with rootless tweak injection, including
an iPhone 11 Pro on iOS 18.6 / Dopamine. This is not a claim that every iOS 18 model,
Settings implementation, language, replacement battery, or private API variation
has been tested. It does not add jailbreak support to otherwise unsupported devices.

For a first device check:

- Confirm all five rows appear once immediately below Maximum Capacity.
- Check Current Charge in mAh and watch it refresh while the page remains open.
- Check Current Discharge Rate in mA while unplugged. While charging, confirm
  the row shows Charging when the reported signed current is positive.
- Compare the mAh readings to the corresponding raw fields in Copy Battery Details.
- Turn Hide Battery Message on and off, reopening the battery page each time.
- Turn Enable Tweak off and confirm the original rows and message return.
- If something is missing or the page crashes, share the relevant crash report or
  copied battery details. Nothing is collected or sent automatically.

## Build from source

Requires Theos, its Preferences/Substrate headers and rootless libraries, Python 3,
an iPhoneOS SDK, and an iOS compiler/linker with arm64e support. The supplied
Makefile defaults to SDK 16.5 with an iOS 18.0 deployment target; a newer SDK is
also usable by overriding `TARGET`.

With a modern Apple toolchain:

```sh
export THEOS=/path/to/theos
make clean package TARGET=iphone:clang:latest:18.0
```

With a legacy Linux arm64e toolchain:

```sh
export THEOS=/path/to/theos
make clean package \
  BC18_ALLEMANDE=/path/to/allemande \
  BC18_LDID=/path/to/ldid
```

The stage script detects legacy arm64e slices, runs the actual allemande
Objective-C ABI conversion, updates the ABI markers in the Mach-O headers, and
re-signs both the tweak and preference bundle. It does not merely relabel an
unconverted binary. If the tools are missing it fails instead of packaging an
incompatible legacy slice. Modern ABI slices are left unchanged. There is no
`oldabi` runtime dependency and no Swift or Cephei dependency.

Callbacks use selectors and C function pointers. Neither binary contains
compiler-generated Objective-C block objects; the package verifier enforces this
because the legacy compiler's block-object ABI caused the 1.0.0 startup crash.

The supplied `.deb` was compiled with the L1ghtmann clang 11.1 iOS toolchain and
SDK 16.5, converted with allemande, and signed ad hoc. Conversion enables this
build route but is not a substitute for testing the result on a device.

Native capacity, current-charge, amperage and warning-filter regression tests:

```sh
sh tests/run.sh
```

Package and code-signature verification:

```sh
python3 scripts/verify_package.py packages/com.brooktrout12.batterycapacity18_1.0.5_iphoneos-arm64.deb
```

## Source layout

- `Tweak.m`: scoped Settings hooks, row insertion, warning filtering, refresh wiring.
- `BCBatteryReader.m`: internal battery discovery and asynchronous readings.
- `CapacityRules.c`: field selection and ratio calculation, shared with native tests.
- `AmperageRules.c`: signed-current decoding and source selection, shared with native tests.
- `WarningRules.c`: warning text recognition and section-removal policy, shared with native tests.
- `prefs/`: PreferenceLoader settings bundle with two switches and a copy button.
- `scripts/`: reproducible ABI conversion and package verification.
- `artwork/`: editable SVG icon; `python3 scripts/render_icon.py` regenerates
  the included 1x/2x/3x PNG files using Pillow. Building the tweak does not require Pillow.
- `tests/`: regression coverage of capacity/current selection and warning section removal.

## References

Primary implementation references consulted; external code and build tools are
not included in this source archive:

- [ChargeLimiter's battery-field documentation](https://github.com/lich4/ChargeLimiter#readme)
  and [registry reader](https://github.com/lich4/ChargeLimiter/blob/main/ChargeLimiter/daemon.mm).
- [Battery Health Enabler's Settings bundle/controller integration](https://github.com/PoomSmart/Battery-Health-Enabler/blob/master/Tweak.x).
- [Theos rootless packaging and ABI requirements](https://theos.dev/docs/rootless).
- [Theos arm64e deployment notes](https://theos.dev/docs/arm64e-deployment).
- [allemande ABI converter](https://github.com/p0358/allemande).

This tweak's source is provided under the MIT license below. External build tools
and Apple SDKs retain their own licenses and are not redistributed here.
