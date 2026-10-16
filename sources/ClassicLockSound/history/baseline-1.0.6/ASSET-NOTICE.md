# Corrected lock audio — ClassicLockSound 1.0.6

The user supplied `lock (mp3cut.net).wav` to correct the previous sound. Its exact bytes are retained as `assets/lock-corrected.wav` (SHA-256 `8fad6338e6fe6b4d3d645ec4240b226c25c970a6d8ae544b0dbbf101ca682c74`).

The installed `layout/Library/Application Support/ClassicLockSound/lock.caf` is a CAF container holding the same 44,100 Hz, stereo, signed 16-bit little-endian PCM samples. No gain, filtering, trimming, resampling, or lossy encoding was applied. Both files decode to the same 39,029 audio frames (approximately 0.885 seconds).

CAF SHA-256: `f1974dfb867c73043b3dbdb902f4f759aa652932b5583eb224d0733bc36d3918`.

Conversion command:
```sh
ffmpeg -i assets/lock-corrected.wav -map 0:a:0 -c:a copy -map_metadata -1 -f caf 'layout/Library/Application Support/ClassicLockSound/lock.caf'
```

`scripts/verify_audio.py` verifies file hashes, audio format, frame count, and decoded sample equality. `scripts/verify_package.py` verifies that the final DEB contains this exact CAF. The previous audio is retained only under `history/baseline-1.0.5/` and is not installed.

The audio remains subject to its original ownership and license. The MIT license applies to the tweak code and supporting scripts, not the audio asset.
