# PhotoIcon 1.1.1

By **Brooktrout12**. Package identifier: `com.brooktrout12.photoicon`.

Choose a photo for an individual app or Safari Home Screen bookmark, move and
scale it, and save it as the icon. Built for rootless iOS 18, arm64 and arm64e.

Version 1.0's Home Screen editing, bookmark support, and animated Save/Cancel
were reported working on an iPhone 11 Pro with iOS 18.6 and Dopamine 3.0.9.
Version 1.1 added image providers for closed-folder miniatures, Spotlight/Siri
Suggestions, app-switcher icons, and standard app-icon requests in Settings
and share sheets. The user confirmed this coverage, then reported a SpringBoard
crash during app switching. Version 1.1.1 fixes the identified background-rendering
transaction bug. That fix still requires confirmation on the device.

## Install and use

1. Install `com.brooktrout12.photoicon_1.1.1_iphoneos-arm64.deb` over the existing
   Brooktrout12 version of PhotoIcon. No uninstall is needed for this update.
2. Respring. Existing icon choices are published for the new consumers automatically.
3. Close and reopen Settings or other apps that were already running if they
   continue to show an old icon. Those processes need the new provider loaded.
4. Long-press an app or Safari bookmark icon and choose **Change Icon…**.
5. Pick a photo, drag and zoom it into position, then tap **Save**.

**Adjust Icon…** reopens the saved photo and crop. **Restore Original Icon**
removes that one override from both the Home Screen and shared catalog.
Cancel leaves the existing choice intact. Save and Cancel slide the editor
down; Reduce Motion uses a short fade.

From an already configured root shell, installation can also use:

```sh
dpkg -i /path/to/com.brooktrout12.photoicon_1.1.1_iphoneos-arm64.deb
```

Respring using the jailbreak's existing controls. Installation does not
restart SpringBoard automatically.

## Coverage

| Surface | Implementation in 1.1 |
| --- | --- |
| Home Screen apps and bookmarks | Existing editor and per-view artwork, plus shared SpringBoard image providers |
| Icons inside open folders | Existing per-view artwork |
| Closed-folder previews | Miniature image and layer providers; folder caches refreshed after changes |
| Spotlight and Siri Suggestions | SearchUI image loading, external SpringBoardHome providers, and IconServices |
| App-switcher small icons | SpringBoard image/layer providers and UIKit/IconServices application-icon requests |
| Settings app entries | UIKit/IconServices application icons |
| Share-sheet app entries | UIActivity and SharingUI app-icon paths; extensions resolve to their containing app |

This is broader app-icon coverage, not a guarantee that every image in every
app is replaced. A third-party app can supply its own artwork without an app
identifier. Settings category symbols, contact avatars, document thumbnails,
AirDrop/Copy action symbols, widgets, and the contents of app-switcher
snapshots are outside the scope. Some consumers retain already-rendered
images; reopening their screen or restarting that app can be necessary after
changing or restoring an icon. Appearance variants and interaction with other
icon tweaks still need device testing.

## Storage and privacy

Original photos, normalized source images, and crop settings remain in:

`/var/mobile/Library/Application Support/PhotoIcon`

The system provider reads only the finished 512 × 512 cropped icons from a
separate cache under the jailbreak root:

`/var/jb/var/mobile/Library/Caches/PhotoIcon`

The cache path follows the loaded tweak if the jailbreak root is relocated.
The installer makes only that cache directory writable by mobile. No extra
sandbox-bypass library, network service, Photos access, or messaging service
is added. Dopamine already provides read access to its jailbreak root for
injected processes. The read-only provider does not load the photo editor.

App bundles, bookmark URLs, and original application icon files are not
modified. Removing the tweak and restarting affected processes restores
native artwork. Saved editing choices remain until you remove the private
PhotoIcon directory yourself. The cropped export cache can also be deleted
after uninstalling if you want to remove every saved copy.

Two bookmarks to the same website retain separate identities. Deleting and
recreating a bookmark gives it a new identity. Folders themselves, widgets,
and App Clips are not selectable for editing.

There is no menu-step diagnostic recorder. See `CRASH-FIX-1.1.1.md`,
`RELEASE-1.1.md`, and `BUILD.md` for implementation details and validation limits.
