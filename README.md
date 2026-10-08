# VHS Camcorder

An iPhone camera that shoots through a live VHS filter. What you see in the viewfinder is exactly what gets saved: the tape look and the camcorder OSD (REC, counter, date) are burned into every clip and photo. There's no clean copy and no editing step. One filter, one mode.

## Features

- Live VHS look: reduced horizontal resolution, chroma smear and bleed, tracking wobble, grain, scanlines, lifted blacks
- Burned-in OSD in a VCR font: `REC` with a running counter while recording, `STBY` when idle, today's date
- Video (H.264 + AAC) and still photos (JPEG), saved straight to Photos
- 4:3 landscape or 3:4 portrait, switched with an on-screen button (no auto-rotate)
- Back and front cameras, 0.5x / 1x / 2x / 3x presets, pinch to zoom up to 10x
- Torch, haptics, and a last-shot thumbnail that opens Photos

## Requirements

- iPhone running iOS 26 or later (camera work needs a real device, the simulator has no camera)
- Xcode with the Metal toolchain installed: `xcodebuild -downloadComponent MetalToolchain`

## Build

1. Open `VHSCamcorder/VHSCamcorder.xcodeproj`.
2. Under Signing & Capabilities, select your team and, if needed, change the bundle id.
3. Pick your iPhone as the run destination and run.

The first launch asks for camera, microphone, and Photos (add-only) access.

## How it works

```
AVCaptureSession (1080p30 BGRA + mic)
  └─ CameraSession
       crop to 1440x1080 (or 1080x1440) → composite OSD → VHS Core Image kernel
       render once into a pooled pixel buffer
         ├─ AVSampleBufferDisplayLayer   (preview)
         └─ AVAssetWriter                (.mov → Photos)
```

Each frame is rendered once and goes to both the preview and the recorder, so the preview never differs from the saved file.

| File | Role |
|---|---|
| `CamcorderView.swift` | The whole UI: housing, shutter, buttons, zoom, toast |
| `CameraSession.swift` | Capture session, camera selection, rotation, zoom, torch, recording, photos |
| `VHSFilter.swift` | Crop, overlay composite, kernel, pixel buffer pool |
| `VHS.ci.metal` | The look |
| `OverlayRenderer.swift` | REC/STBY, counter, and date overlay |
| `VideoRecorder.swift` | Writes one recording and saves it to Photos |

## Tuning the look

All the knobs are constants at the top of `VHSCamcorder/VHSCamcorder/VHS.ci.metal`:

| Constant | Effect |
|---|---|
| `kHorizontalRes` | Effective horizontal resolution (lower is blurrier) |
| `kChromaBlur` | How far color smears horizontally, in px |
| `kChromaShift` | How far color lags to the right of luma, in px |
| `kSaturation` | Color saturation |
| `kWobble` | Tracking jitter, in px |
| `kNoise` | Grain strength |
| `kScanline` | Scanline darkness |

## Credits

OSD font: VCR OSD Mono by Riciery Leal.
