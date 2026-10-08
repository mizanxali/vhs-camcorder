# Roadmap

What it takes to make VHS Camcorder a polished one-time purchase. Ordered by what earns the price tag soonest. Each item is sized to be one phase: implement, build to device, check, stop.

## Phase 0: Ship blockers

- **Permission-denied state.** Camera denial leaves a black viewfinder with no explanation. Add one "Camera access needed" view with an Open Settings button, same for Photos add-only denial. App Review rejects without it.
- **App icon.** The asset catalog has no AppIcon set. Needs the icon, App Store screenshots, and a short preview video shot in the app.
- **Privacy manifest.** No `PrivacyInfo.xcprivacy` in the project. Required for submission. Trivial since nothing is collected.
- **Temp file sweep.** A crash mid-recording leaves the .mov in the temp directory forever. One line on launch to clear leftover .mov files.
- **Disk space guard.** Check free space before starting a recording and refuse with a toast under ~500 MB. Otherwise the writer fails at the end and the clip is lost silently.
- **VoiceOver labels.** Photo, flip, torch, orientation, thumbnail and zoom buttons are icon-only with no labels. Honor Reduce Motion on the pulsing shutter.
- **Session recovery.** Recording stops on interruption, but the session is never restarted after a phone call or Control Center video. Observe the interruption-ended notification and resume.

## Phase 1: Camera table stakes

- **Tap to focus and expose.** Focus and exposure point of interest on tap, long-press to lock, a VHS-style bracket that fades. (Exposure sliders stay out of scope.)
- **Video stabilization.** One line on the connection. VHS wobble is charming, raw phone shake is not.
- **Hardware shutter.** Volume buttons and the Camera Control button via a single `AVCaptureEventInteraction`. Also lets the app launch from Camera Control.
- **Auto-rotate while idle.** Follow device orientation when idle, lock once recording starts, keep the button as an override. Changes an existing design decision; decide before building.
- **Press-and-hold zoom rocker.** A W/T rocker that ramps while held. More on-brand than presets, reuses the existing ramped zoom.
- **Review prompt.** Request a rating after the fifth saved clip.

## Phase 2: The look

What separates a paid app from the free ones. All of it lives in the kernel or one small settings sheet.

- **Date override and time.** The most requested feature in this category; people set the OSD to a year from their childhood. Real camcorders show the time next to the date. Long-press the viewfinder to open a small sheet with a date picker, stored with `@AppStorage`. This is the one settings surface the app needs.
- **Title card.** Optional text like SUMMER 98 shown for the first few seconds of a clip. Same sheet as the date.
- **Head-switching noise bar.** The tearing band at the bottom of every real VHS frame. Ten lines in the kernel and the most recognizable missing tell.
- **Tape wear events.** Occasional tracking glitch band sweeping down, random white dropout streaks, subtle vignette. Time-driven, no settings, every clip looks different.
- **Audio degradation.** Currently listed as not built, but audio is half the feel. Low-pass biquad plus tape hiss on the PCM samples before the writer, a few dozen lines with vDSP.
- **Three tape speeds instead of an intensity slider.** SP, LP, EP as one three-way toggle scaling the existing constants. Keeps the one-filter identity while giving a choice.

## Phase 3: Import existing media

VHS-ifying old videos and photos from the library is the biggest reason someone pays. Reuses the whole filter path: `AVAssetReader` feeds the same `VHSFilter` and a `VideoRecorder`-style writer, with a progress toast. Photos go through the existing JPEG path. Largest item on the list; its own phase.

## Phase 4: Delight

- Camcorder sounds on record start/stop and a shutter click for photos, played before the writer starts so they never bleed into the clip.
- Battery bars on the OSD from the device battery level.
- Save into a "VHS Camcorder" album in Photos.
- Share sheet on long-press of the last-shot thumbnail.
- Control Center control and App Shortcut to open straight into recording.

## Not building

In-app gallery, cloud sync, social features, accounts, third-party analytics or crash SDKs. Xcode's crash reports cover the last one for free.
