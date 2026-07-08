# Vendored deviation: live speech-to-text tap (a.k.a. "D6")

**Status: PLANNED — not yet applied.** Lands when the audio delay is first turned
on, i.e. the UXIRL two-phone camera topology / burned-in captions (spec Phase 2:
`UXIRL/specs/product-specs/camera-and-streaming.md`, decision D6). Documented here
now so the rationale and exact edit aren't lost, and so `sync-upstream.sh` drift on
`AudioUnit.swift` is reviewed against it.

**File:** `Sources/IRLStreamKit/Vendor/Media/HaishinKit/Media/Audio/AudioUnit.swift`
**Marker to add at the edit sites:** `// UXIRL: live STT tap (D6)`

## Why

On the producer, one mic feed serves two consumers with opposite timing needs:

```
                       ┌─ STREAM leg  → DELAYED (+~350 ms) to line up with the late
   mic ──▶ your voice ─┤                 remote-camera video (lip sync)
                       └─ CAPTION leg → LIVE (0 ms) so speech-to-text fires early
```

Speech-to-text should run on **live** audio so subtitles appear fast; the encoded
stream must be **delayed** so the operator's mic lines up with the remote camera's
late video. The vendored path puts the caption tap *downstream* of the delay, so
turning the delay on drags captions with it.

**The bug is latent.** With `builtinAudioDelay == 0` (the facade default today, and
the standalone single-phone case) `appendBufferedBuiltinAudio` returns `nil`, the
mic buffer is never delayed, and the tap already gets live audio — nothing to fix.
The defect only appears once `builtinAudioDelay > 0`.

## Current flow (unpatched)

`captureOutput` (AudioUnit.swift ~357):

```
captureOutput(didOutput: sampleBuffer)                                [357]
  pts = syncTimeToVideo(...)                mic PTS → video clock      [366]
  var sampleBuffer = sampleBuffer           ← LIVE buffer             [367]
  if let b = appendBufferedBuiltinAudio(sampleBuffer, pts) {          [368]
      sampleBuffer = b.getSampleBuffer(...)  ← reassigned to DELAYED  [369]   (+D stamped at 313)
  }
  guard selectedBufferedAudioId == nil else { return }               [371]   (mic is program audio)
  appendNewSampleBuffer(processor, sampleBuffer, pts)                [374]
```

`appendNewSampleBuffer` (~277):

```
  mute / gain                                                        [281]
  audio level meter                                                  [284-292]
  if speechToTextEnabled {                                           [293-295]
      processor.delegate.streamAudio(sampleBuffer)   ◀── CAPTION TAP (post-delay)
  }
  encoder.appendSampleBuffer(...)   → AAC → stream                   [297]
  recorder.appendAudio(...)                                          [298]
```

By line 369 `sampleBuffer` is the delayed buffer, and the tap at 294 runs after
that. So with the delay on, the transcriber receives audio ~D late.

## The patch

Fork the caption leg off the **live** buffer in `captureOutput`, before the delay
swap, and remove the post-delay tap from `appendNewSampleBuffer`.

In `captureOutput`, immediately after `var sampleBuffer = sampleBuffer` (367) and
**before** `appendBufferedBuiltinAudio` (368):

```swift
// UXIRL: live STT tap (D6) — transcription must see undelayed mic so captions
// stay prompt while the stream leg is delayed to match remote video. See
// docs/divergences/speech-to-text-live-tap.md.
if speechToTextEnabled, selectedBufferedAudioId == nil, !muted {
    processor.delegate.streamAudio(sampleBuffer: sampleBuffer)
}
```

In `appendNewSampleBuffer`, delete the existing block (293-295):

```swift
if speechToTextEnabled {
    processor.delegate.streamAudio(sampleBuffer: sampleBuffer)
}
```

Net: ~4 lines relocated. The caption leg forks live (0 ms); the stream leg keeps
its delay.

### Two deliberate choices in the guard

- **`!muted`** — preserves current semantics (a muted mic produces no captions).
  The old tap sat *after* mute/gain (281); the new one sits before it, so the mute
  check is re-added explicitly.
- **`selectedBufferedAudioId == nil`** — transcribe only the local mic, never a
  selected network-audio source (`didOutputBufferedSampleBuffer` → `appendNewSampleBuffer`
  also carried the old tap). We never caption remote audio, and this prevents any
  double-fire.

## The patch alone does nothing visible

It only makes live audio *available*. The rest is additive, no vendor edits:

```
VENDOR   AudioUnit.captureOutput ─streamAudio()▶ Media.streamAudio (1117)
         └▶ Media.delegate.mediaOnAudioBuffer(buf) (1118)
FACADE   MediaDelegateAdapter.mediaOnAudioBuffer(_) {}   ← empty today (:105); forward it out
         expose builtinAudioDelay (IRLStreamEngine.swift:276 hardcodes 0 → make settable)
APP      UXIRL CaptionEngine: SpeechAnalyzer → audioTimeRange → SubtitleTrack → burn-in
```

## Verify after applying / after a sync

1. `scripts/sync-upstream.sh` will report `AudioUnit.swift` as drifted — expected;
   re-apply this edit if upstream overwrote it (check whether upstream restructured
   `captureOutput`/`appendNewSampleBuffer` first).
2. Delay OFF (`builtinAudioDelay == 0`): behavior identical to upstream — the tap
   fires on the same (live) buffer either way.
3. Delay ON (`builtinAudioDelay > 0`): the buffers handed to `streamAudio` carry
   PTS ~D **earlier** than the buffers handed to `encoder.appendSampleBuffer`.
   Assert this in a unit test with a fake `ProcessorDelegate` capturing both PTS
   streams.
4. Muting the mic stops caption forwards (the `!muted` guard).
