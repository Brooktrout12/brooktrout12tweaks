# Build and evidence

Updated 2026-10-16. Version 0.2.0 / Test 2.

## Target

- Official listing: https://apps.apple.com/de/app/rock-antenne/id293171171
- Apple's lookup returned bundle `de.rockantenne.eple`, app version `6.2.26`, release date `2026-09-14T06:43:24Z`, minimum iOS `15.6`: https://itunes.apple.com/lookup?id=293171171&country=de
- Test 2 uses guarded runtime checks for the documented AdsWizz interfaces. No physical-device success is claimed.
- The tweak's package and runtime gate permit iOS 17.x and 18.x.

## Evidence

- ROCK ANTENNE identifies AdsWizz and RMSi for stream advertising: https://www.rockantenne.de/rockcommunity/datenschutz/
- Public streaming hosts and mountpoints: https://www.rockantenne.de/rockhoeren/empfang/streamlinks
- The broadcaster's served webplayer script uses `.c-dialog--companion-ad` and `[data-a11y-dialog-hide]` for companion-ad dialogs, and requests `https://synchrobox.adswizz.com/register2.php`. Observed script: https://www.rockantenne.de/dist/websites/main.533tr7afu8s0.js
- AdsWizz documents that stream metadata can cause a direct-selection VAST request for additional ad information: https://api.sdk.adswizz.com/ios/AdswizzSDK/Classes/AdStreamManagerSettings.html
- The public `AASDKAdManager` protocol exposes `skipAd`, `prepare`, `play` and delegates. Test 2 checks the loaded Objective-C protocol and method encodings before using these: https://api.sdk.adswizz.com/ios/AdswizzSDK/Protocols/AdManager.html
- Public stream delegate callbacks include ad break start/end and reconnect: https://api.sdk.adswizz.com/ios/AdswizzSDK/Protocols/AdStreamManagerDelegate.html
- Client-side event and ad-object properties: https://api.sdk.adswizz.com/ios/AdswizzSDK/Protocols/AdManagerDelegate.html and https://api.sdk.adswizz.com/ios/AdswizzSDK/Protocols/AdEvent.html
- SDK integration guides describe skipping and the resulting transition to the next ad/content: https://docs.sdk.adswizz.com/iOS/SDKiOS/ServerSideInsertion.md and https://docs.sdk.adswizz.com/iOS/SDKiOS/ClientSideInsertion.md
- Apple excludes background download sessions from custom URLProtocol: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/protocolclasses
- Supported WebKit APIs: https://developer.apple.com/documentation/webkit/wkcontentruleliststore and https://developer.apple.com/documentation/webkit/wkusercontentcontroller

The fetched API reference identifies SDK 7.14.2. The actual app's SDK version and callbacks are checked/logged at runtime. Public documentation motivates this fix; it does not establish that the app uses every documented Objective-C entry point. Swift-only/internal dispatch may bypass an installed Objective-C hook.

Test 2 allows native AdsWizz delivery when skip hooks are installed so the SDK can identify and skip managed ads. This is an experimental approach; it does not rewrite stream URLs or infer an undocumented ad-free endpoint.

## Toolchain and architecture

- Theos commit `5280bd038207e14f8bd76f5417aa2fe641c03228`.
- L1ghtmann Clang 11.1.0 (`test-210562a`), iPhoneOS16.5.sdk declarations; deployment target iOS 17.0.
- Standard **arm64** Mach-O, rootless `iphoneos-arm64` packaging.
- Only the App Store process is targeted. App Store apps use arm64, including on A12+ devices; they do not require the arm64e system-process ABI: https://theos.dev/docs/rootless
- No arm64e conversion or `oldabi` dependency is used. This avoids the older toolchain's arm64e block-metadata issue; arm64 supports the required callbacks directly.
- The minimal SDK omits WebKit. `WebKitAPI.h` declares the public method subset used. Actual classes are loaded from iOS's system WebKit and resolved at runtime. No substitute framework is implemented.
- Hooks use Objective-C runtime method replacement. The `mobilesubstrate` package dependency represents compatible jailbreak injection.

Toolchain sources:

- https://github.com/theos/theos/tree/5280bd038207e14f8bd76f5417aa2fe641c03228
- https://github.com/L1ghtmann/llvm-project/releases/tag/test-210562a
- https://github.com/theos/sdks/releases/tag/master-146e41f

## Verification boundary

Reports are in `validation/`. Verification reads the DEB payload and checks injection scope, iOS minimum, dependencies, and actual SHA-256 code-page hashes. Host tests cover provider boundaries and public radio hosts. The skip-gate test checks duplicate requests, cancellation after ad end, rejection of stale callbacks after a new break, and the bounded attempt limit. The JavaScript test executes the embedded script and checks dialog closing, domain isolation, deduplication, and URL-parameter redaction.

Outstanding for Test 2: installation/launch, actual SDK hook execution and skip behavior, ad availability and audible results, stream reconnection, WebKit behavior, diagnostic sharing, background playback and crash behavior on physical iOS 17/18 devices. A waiting AVPlayer, a blocked request, a skip invocation, or a playing state alone cannot establish ad-free content.
