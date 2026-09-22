# VHS Camcorder

Native iOS app (SwiftUI, iOS 26+, iPhone only, landscape or portrait) that records video through a live VHS filter and saves it to Photos. One filter, one mode. The project lives one level down at `VHSCamcorder/VHSCamcorder.xcodeproj`, bundle id `com.mizanxali.VHSCamcorder`.

## How it works

One frame path, rendered once, fanned out to two consumers:

```
AVCaptureSession (virtual multi-lens back camera or front camera, 1080p30 BGRA, mic)
  └─ CameraSession (delegate on a serial queue)
       CIImage → aspect-fill crop to 1440x1080 (4:3) or 1080x1440 (3:4 portrait) → OSD overlay composited → VHS CIKernel
       CIContext.render(to: pooled CVPixelBuffer)
         ├─ AVSampleBufferDisplayLayer   (preview; shows exactly what gets encoded)
         └─ VideoRecorder                (AVAssetWriter H.264 + AAC → temp .mov → Photos)
```

The filter and the overlays are baked into the file. There is no clean copy.

## Files (`VHSCamcorder/VHSCamcorder/`)

| File | Role |
|---|---|
| `CamcorderView.swift` | The whole UI: housing, shutter, flip, torch, zoom presets, pinch, toast. Palette constants at the top. |
| `CameraSession.swift` | Capture session, camera selection, rotation, zoom, torch, recording start/stop, frame callback. |
| `VHSFilter.swift` | Crop, overlay composite, kernel apply, pixel buffer pool. |
| `VHS.ci.metal` | The look. Tuning constants at the top of the file. |
| `OverlayRenderer.swift` | REC/STBY, counter, date drawn with UIKit into a cached transparent CIImage, once per displayed second. |
| `VideoRecorder.swift` | One recording. `finish()` returns whether the clip reached Photos. |
| `PreviewView.swift` | UIView host for the display layer. |

## Build, install, run from the CLI

Camera work needs a real device. The iPhone's device id and the stable DerivedData path:

```sh
cd VHSCamcorder
xcodebuild -scheme VHSCamcorder -destination 'id=00008140-0004453A212B001C' -configuration Debug build -quiet
APP=~/Library/Developer/Xcode/DerivedData/VHSCamcorder-egnypmmfkzzwsgaqxwfksyeiaaxc/Build/Products/Debug-iphoneos/VHSCamcorder.app
xcrun devicectl device install app --device 00008140-0004453A212B001C "$APP"
xcrun devicectl device process launch --terminate-existing --device 00008140-0004453A212B001C com.mizanxali.VHSCamcorder
```

There is a second, stale `VHSCamcorder-*` folder in DerivedData. Do not glob; use the path above or resolve `BUILT_PRODUCTS_DIR` from `-showBuildSettings`.

## Things that bit us

- **Core Image Metal kernels need explicit flags.** Xcode 27 did not pick up the `.ci.metal` extension automatically. The target sets `MTL_COMPILER_FLAGS = -fcikernel` and `MTLLINKER_FLAGS = -fcikernel`. The Metal toolchain is a separate download: `xcodebuild -downloadComponent MetalToolchain`.
- **Sampler space is not pixel space.** In the kernel, do all coordinate math on `dest.coord()` and sample through `src.transform(...)`. Adding pixel offsets to `src.coord()` clamps every tap to the edge and smears each row into one color.
- **Default MainActor isolation is on** (Swift approachable concurrency). Classes that run on the capture queue are declared `nonisolated` and `@unchecked Sendable`; anything touching UIKit or the display layer's init is `@MainActor`.
- **Virtual camera zoom factors.** On the triple/dual-wide device, raw `videoZoomFactor` 1 is the ultra-wide. `CameraSession` records the first `virtualDeviceSwitchOverVideoZoomFactors` entry as "1x" and exposes display factors (0.5x, 1x, 2x, 3x) to the UI. Digital zoom is capped at 10x.
- **Orientation.** `CameraSession` rotates the capture connection (0/90/180/270) and sets `filter.outputSize`. The front sensor is mounted 180° from the back one, handled in `applyRotation()`. The connection is recreated on every input change, so rotation and mirroring are reapplied after each flip. A clip keeps the orientation it started in; rotation changes are held until `stopRecording()`. There is no auto-rotate: `AppDelegate.orientationLock` is `.portrait` or `.landscapeRight`, flipped only by the orientation button in `CamcorderView` (disabled while recording). The UI switches on `verticalSizeClass`.
- **Recording stop is async** and returns the Photos save result. The toast waits on it, so it appears a beat after the button press.

## Working conventions

- Never commit. The user commits their own work with conventional-commit messages (`feat:`, `style:`, `init:`). Leave changes in the working tree and suggest a one-line message.
- Work in phases when asked for a plan: implement, build to the device, report what to check, stop.
- Keep the ladder: no new dependencies, no settings screens, no abstractions for one use. Tuning happens in constants at the top of `VHS.ci.metal` and `CamcorderView.swift`.

## Not built on purpose

Custom VCR font (system monospaced bold is close enough), VHS audio degradation, exposure controls, in-app gallery, filter intensity slider, unit tests (it is AV pipeline glue verified on device).
