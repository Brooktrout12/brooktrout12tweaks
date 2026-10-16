# Audio and Settings icon

`assets/lock-original.caf` and the installed `layout/Library/Application Support/ClassicLockSound/lock.caf` are the exact original asset from Classic Lock Sound 1.0.5, restored at the user's request.

SHA-256: `90d02d979ff94defa18b05ca91ba8633a7eb73f28574b015af09d542d8331543`.

Format: CAF version 1, stereo signed 16-bit little-endian PCM, 44,100 Hz, 39,047 frames, 160,284 bytes. At 100% this complete file remains unchanged. `BTVolume.c` scales only the PCM samples at lower settings, with symmetric nearest-integer rounding, preserving the container metadata and duration. There is no resampling, filtering, trimming, lossy encoding, or gain above 1.0.

CAF format reference: https://developer.apple.com/library/archive/documentation/MusicAudio/Reference/CAFSpec/CAF_spec/CAF_spec.html

The audio remains subject to its original ownership and license. The MIT license covers the tweak code and supporting scripts, not the audio recording.

## Settings icon

The new blue/cyan lock-and-sound icon was generated for this release. The untouched generated PNG is included as `assets/settings-icon-master.png` (1254 × 1254 RGBA). Pillow's LANCZOS resampling produced the installed `prefs/Resources/icon.png` (29 × 29), `icon@2x.png` (58 × 58), and `icon@3x.png` (87 × 87). These are packaging resizes of the selected generated artwork.

Generation brief: one finished iOS Settings pane icon for Classic Lock Sound; a clean square PNG with a polished native iOS blue/cyan rounded-square tile and transparent exterior, a bold white closed padlock slightly left of center and two white sound-wave arcs on the right; precise geometry legible at 29 × 29, subtle blue gradient, no text, phone mockup, or external shadow. The requested 1024-pixel format was returned at 1254 pixels; the master is retained at its returned size.
