# Spatial Studio

[简体中文](README.zh-CN.md)

Spatial Studio is a macOS app for positioning live system audio around your head while listening through headphones. Move one stereo source for a distinct position, or assign different apps to separate sources.

- Position, zoom and rotate the sound field. Click a direction marker for close placement, or drag a point onto the center of the head.
- Use automatic movement presets for orbits, sweeps and changes in distance. Dedicated close-rear and rear-crown presets are grouped together.
- Adjust angle, height, distance, speed and gain during movement. Solo any point to compare it with the full mix.

## Build and run

**macOS 26 or later only.** Use Xcode 26 or later with its command-line tools, Python 3, and OpenSSL (the LibreSSL included with macOS also works).

```sh
git clone https://github.com/ff-fdt/spatial-studio-macos.git
cd spatial-studio-macos
./scripts/build-app.sh
open "dist/Spatial Studio.app"
```

The build script signs the app locally. Put on headphones and click **Start processing**. The first time, allow Spatial Studio under **Screen & System Audio Recording** in macOS Privacy & Security. Click **Bypass** or quit to restore normal playback.

The app follows the macOS language setting and includes English and Simplified Chinese. Run the audio and motion tests with `swift test`.

## License and credits

Project source is under the [MIT License](LICENSE). Third-party components retain their own licenses:

- [atmos-control](https://github.com/yukij3/atmos-control/tree/3e62fc3/Sources/SpatialEngine) — audio engine foundation, [MIT](Sources/SpatialEngine/LICENSE-atmos-control.txt).
- [Spatial Audio Framework distance model](https://github.com/leomccormack/Spatial_Audio_Framework/blob/18fd5ab/framework/modules/saf_utilities/saf_utility_dvf.c) — near-field compensation, [ISC](Sources/NearFieldDVF/LICENSE.txt).
- *Infinite, 3D Head Scan*, Lee Perry-Smith / Infinite Realities — adapted geometry under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), with [source and modification details](Sources/SpatialDesk/Resources/HeadScan-Attribution.txt).
