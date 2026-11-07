# CC17Shapes 1.0.3

By **brooktrout12**. A standalone rootless tweak for iOS 18.x.
No settings to configure.

Gives Control Center's rounded controls a consistent iOS 17-style corner size:

- Single controls, wider tiles such as Focus, and large connectivity/media panels.
- Brightness, volume and stepped flashlight sliders, using native corner controls.
- Native layout geometry used by editing outlines and Add a Control previews.
- The inner connectivity buttons stay circular, including in the expanded group.

## Install or update

Open `com.brooktrout12.cc17shapes_1.0.3_iphoneos-arm64.deb` in your package manager
or Filza's package installer, install the update, and respring. It replaces
CC17Shapes 1.0.2 under the same package identifier. CCFavorites and PageDotsOnly
remain separate tweaks.

Uninstall CC17Shapes and respring to restore native shapes. No saved layout,
preferences, system files or button actions are changed.

## What changed in 1.0.3

- The expanded flashlight now receives the same radius in its stepped-slider
  override and base implementation. Its step container is refreshed after
  attachment/layout when needed, addressing the mix of round and squared layers.
- Focus rows now use the shared radius in FocusUI's own frame-based corner
  calculation. Background creation, attachment and layout also apply the shape,
  addressing the DND row that only corrected itself after expansion/collapse.

These changes preserve the existing shared corner policy and the round inner
connectivity-button exception. They do not change flashlight levels, slider
interaction, Focus selection, duration menus or actions.

## Shape policy introduced in 1.0.2

Version 1.0.1 reshaped circular controls but deliberately preserved the existing
rounded panels and sliders. That left different corner sizes in the same grid.

Version 1.0.2 uses one quarter of the native single-cell width as the shared
corner radius for larger controls too. It does not calculate a larger radius
from the width of a 2x2 panel. The gallery uses its own grid scale, and very small
submenu buttons keep proportionally smaller corners. Existing sharp-edged fills
remain sharp. Native layer backgrounds use continuous corners.

The connectivity exception now applies specifically to the inner round buttons
and their presentation subtrees. The outer connectivity panel is included in
the consistent corner rule. Slider changes go through the native slider radius
API so iOS continues to control the fill boundary and elastic dragging behavior.

## Validation

**Version 1.0.3 passed compilation, geometry checks and package verification.**
These host checks do not establish on-device behavior. Both arm64 and arm64e
device slices are included.

The checks cover equal corner sizes across small/wide/tall/large controls,
gallery scaling, repeated setters, invalid dimensions, rootless dependencies,
package identity, converted arm64e metadata and signature page hashes. Reports
are included as `geometry-verification.json` and `verification.json`.

After installing and respringing, expand the flashlight and check its full outer
shape at every brightness step. Then open Focus and check DND before touching
its options button; the row should already have the same corners as Sleep,
Personal and Work. Expand and collapse its duration menu and reopen Focus to
check reuse. Host tests cannot verify these UIKit transitions.

Private hooks are checked against runtime method signatures. Unsupported custom
image-backed or custom-path backgrounds may retain their original shape. The
tweak records no diagnostics and installs no preferences pane.

## Source

`Tweak.m` contains the hooks and scoped presentation changes. `BTShapeGeometry.h`
contains the radius policy. `tests/` and `scripts/` contain the host checks and
build helpers. Matching debug symbols are included under `debug/` for developers;
they are not installed on the phone. See `BUILD.md` to rebuild. MIT license.
