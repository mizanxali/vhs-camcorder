# VHS Camcorder iOS app

## Context

Greenfield native iOS app: a single-purpose camcorder that records video through a live VHS filter and saves the result to Photos. No filter picker, no modes. `/Users/mizanxali/vhs-camcorder` is empty. Xcode 27, iPhone on iOS 26.6 available (camera work must be tested on device, not simulator).

## Decisions (agreed)

| Decision | Choice |
|---|---|
| Filter timing | Baked in at record time. Preview and file come from the same filtered frame. |
| Aspect | 4:3, center-cropped from the 16:9 sensor frame (1920x1080 → 1440x1080). |
| Overlays | Blinking REC dot, elapsed time, date stamp. Burned into the video, under the filter so they degrade too. |
| Orientation | Landscape-only camcorder UI (both landscape directions). |
| Filter tech | Core Image + one custom Metal CIKernel (`.ci.metal`, auto-compiled by Xcode 15+, no linker flags). |
| Project | User creates a blank SwiftUI iOS app in Xcode named `VHSCamcorder` in this folder. Claude fills in files. |
| Min iOS | 26 |
| Output | H.264 MOV, 1440x1080, 30fps, AAC audio. Low-res look comes from the shader, not the file size. |

## Architecture

One frame path, rendered once, fanned out to two consumers:

```
AVCaptureSession
  ├─ AVCaptureVideoDataOutput (BGRA, 1080p30) ──┐
  └─ AVCaptureAudioDataOutput ──────────────────┼──► CameraSession (delegate, serial queue)
                                                │
   CIImage(pixelBuffer) → crop 4:3 → composite overlay → VHS CIKernel
                                                │
   CIContext.render(to: CVPixelBuffer from pool)
                                                ├──► AVSampleBufferDisplayLayer   (preview)
                                                └──► AVAssetWriter + pixel buffer adaptor (recording)
                                                       └─ finish → PHPhotoLibrary save → delete temp file
```

Why `AVSampleBufferDisplayLayer` instead of `MTKView`: it displays CVPixelBuffers natively, so the preview is literally the buffer being encoded. No Metal view code, no second render.

### Files (all under `VHSCamcorder/VHSCamcorder/`, Xcode default nested layout)

- `MyApp.swift` — entry point (Xcode-generated, unchanged).
- `CamcorderView.swift` — SwiftUI: 4:3 preview centered on black, record button, flip button. Owns a `CameraSession`.
- `PreviewView.swift` — `UIViewRepresentable` wrapping a `UIView` whose `layerClass` is `AVSampleBufferDisplayLayer`.
- `CameraSession.swift` — session setup, permissions, capture delegate, calls `VHSFilter`, enqueues to preview layer, forwards to `VideoRecorder` when recording. Publishes `isRecording`, `elapsed`.
- `VHSFilter.swift` — loads the kernel from `default.ci.metallib`, builds the per-frame CIImage (crop → overlay → kernel). Holds the `CIContext` and pixel buffer pool.
- `VHS.ci.metal` — the shader.
- `OverlayRenderer.swift` — renders "● REC", "HH:MM:SS", "SEP. 22 2026" to a transparent CGImage via `UIGraphicsImageRenderer`. Cached, regenerated once per second (blink + clock tick).
- `VideoRecorder.swift` — `AVAssetWriter` (H.264 video input + `AVAssetWriterInputPixelBufferAdaptor`, AAC audio input), start on first video frame, finish → save to Photos.

Project-level edits (in `project.pbxproj` build settings, since modern Xcode templates have no Info.plist file):
- `INFOPLIST_KEY_NSCameraUsageDescription`, `INFOPLIST_KEY_NSMicrophoneUsageDescription`, `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`

### Shader design (`VHS.ci.metal`)

Single general `CIKernel` `vhs(sampler src, float time, float width, float height)` with ROI callback padding ~24px horizontally. Effects, in order:
1. Horizontal resolution loss: quantize x sample coordinate to ~1/3 res (≈480 effective lines), plus a 3-tap horizontal blur.
2. Tracking wobble: x offset = small sine of (y, time) + a stronger band that sweeps near the bottom every few seconds.
3. Chroma bleed: convert to YIQ, sample chroma from a wider horizontal blur with a slight rightward offset, luma from the sharp path.
4. Head-switching noise: bottom ~12 rows get random horizontal tear and brightness jitter.
5. Grain: hash noise from (coord, time), stronger in dark areas.
6. Scanlines: alternate rows darkened ~8%.
7. Color: slight saturation lift, lifted blacks, softened whites.

Constants live at the top of the shader as `constant float` so tuning is one file. `// ponytail:` comment noting they are hand-tuned; a settings UI is out of scope.

## Build process

- Phases run one at a time, only when the user says "start phase N".
- Claude implements the phase, builds it against the connected iPhone from the CLI, reports what was done and how to check it on device, then stops.
- The user reviews (runs it, tunes, asks for changes). Nothing from the next phase is started until the user asks.
- Claude never commits. The user reviews and commits each phase themselves.
- This plan lives at `PLAN.md` in the project root and is updated if decisions change.

## Phases

Each phase ends with a device run and a visible result. Nothing in a later phase is scaffolded early.

### Phase 0 — Project creation (user + Claude)
- User: Xcode → New Project → iOS App → name `VHSCamcorder`, SwiftUI, Swift, save into `/Users/mizanxali/vhs-camcorder`. Set signing team.
- Claude: edit `project.pbxproj` for the plist keys, landscape orientation, deployment target. `git init`, `.gitignore` (xcuserdata, DerivedData).
- Verify: `xcodebuild -scheme VHSCamcorder -destination 'id=00008140-0004453A212B001C' build` succeeds.

### Phase 1 — Live 4:3 preview
- `CameraSession`: request camera permission, configure session (back wide camera, `.hd1920x1080`, 30fps, BGRA video data output), set `videoRotationAngle` from the interface orientation so buffers are landscape.
- `VHSFilter` (no shader yet): `CIImage(cvPixelBuffer:)` → center crop to 1440x1080 → render into pooled pixel buffer.
- `PreviewView` + `CamcorderView`: full-black background, 4:3 preview centered, no buttons yet.
- Verify: app shows live unfiltered 4:3 landscape video on device, both landscape rotations correct.

### Phase 2 — VHS shader
- Add `VHS.ci.metal`, load kernel in `VHSFilter`, apply after crop. Pass `time` as seconds since session start.
- Verify: preview shows the VHS look at a steady 30fps (check Xcode CPU/GPU gauges; frame callback must not drop). Tune constants by eye.

### Phase 3 — Record and save to Photos
- Add `AVCaptureAudioDataOutput` and mic permission to `CameraSession`.
- `VideoRecorder`: writer to a temp `.mov`, video input 1440x1080 H.264 with pixel buffer adaptor, audio input AAC. `startSession` at the first video frame's PTS. Audio samples appended only after the session has started.
- `finish()` → `PHPhotoLibrary.requestAuthorization(for: .addOnly)` → `performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:) }` → remove temp file.
- `CamcorderView`: big red record button toggling `startRecording()` / `stopRecording()`. Keep screen awake while the app is foreground (`UIApplication.shared.isIdleTimerDisabled`).
- Handle: stop recording cleanly on background / session interruption so no partial file is lost.
- Verify: record 10s with speech, stop, open Photos: 4:3 filtered clip, correct orientation, audio in sync, plays in QuickTime.

### Phase 4 — Camcorder overlays
- `OverlayRenderer`: transparent 1440x1080 image with "● REC" (red, top-left, hidden on odd seconds while recording; shows "PAUSE"-free "STBY" when idle), elapsed `HH:MM:SS` top-right, date bottom-right in VHS uppercase format. Monospaced bold system font, white with a 1px dark shadow. Regenerated only when the displayed second changes.
- `VHSFilter` composites the overlay over the cropped frame before the kernel.
- Verify: overlays visible in preview and in the saved file, degraded by the filter, REC blinks at 1Hz.

### Phase 5 — Small polish (only what a camcorder needs)
- Flip camera button (front/back), preserving 4:3 crop and rotation.
- Haptic on record start/stop.
- Verify: flip works mid-preview (not mid-recording; button disabled while recording).

## Skipped on purpose
- Custom VCR OSD font: system monospaced bold is close enough. Add a bundled font when the look bothers you.
- Audio degradation (VHS hiss / bandpass): clean mic audio for v1.
- Zoom, torch, exposure controls, settings screen, filter intensity slider, gallery inside the app: out of scope per brief.
- Unit tests: the logic is AV pipeline glue verified on device. One `#if DEBUG` assertion in `VHSFilter` that the kernel loaded is the only check.

## Verification (end to end)

1. Connect the iPhone, build and install from CLI:
   ```
   xcodebuild -scheme VHSCamcorder -destination 'id=00008140-0004453A212B001C' -configuration Debug build
   xcrun devicectl device install app --device 00008140-0004453A212B001C <path to .app>
   xcrun devicectl device process launch --device 00008140-0004453A212B001C <bundle id>
   ```
   Or just Run from Xcode.
2. Grant camera, mic, and photos-add permissions on first launch.
3. Record a clip, confirm it appears in Photos with the filter, overlays, 4:3 frame, audio, correct orientation in both landscape holds.
4. Background the app mid-recording, return: no crash, recording stopped, clip saved.
