# Mimi iPhone feasibility prototype

Scope: user-initiated ReplayKit app-audio capture, local English speech recognition,
English-to-Chinese translation, and a sample-buffer Picture in Picture subtitle view.
This is a device experiment, not a claim of universal app compatibility or App Store readiness.

- React Native remains the launcher. The experiment is an explicit native screen.
- A Broadcast Upload Extension drops video and microphone samples immediately.
- The extension converts app audio to 16 kHz mono PCM and sends bounded frames over
  an authenticated loopback-only connection. No App Group or remote service is used.
- The host requires on-device Speech support and never falls back to cloud recognition.
- Translation uses Apple's downloaded language packs. Downloads require system consent.
- Audio and transcripts are not written to disk. Diagnostic counters contain no transcript.
- Stop closes the receiver and the extension ends when its host connection closes.
- Background lifetime, speech-session duration, other-app compatibility and PiP content
  behavior must be assessed on a physical iPhone.

Build after Expo prebuild / pod install:

```
ruby scripts/configure-ios-prototype.rb
npm run ios:device
```

The Ruby script requires the xcodeproj gem (available through the local CocoaPods bundle).
Native source is kept here because `ios/` is generated and ignored.

## Device evidence — 2026-09-15

On the connected iPhone 17 / iOS 26.4:

- Release host and Broadcast Upload Extension compile and install with the user's personal team.
- English and Simplified Chinese translation resources were prepared through Apple's download sheet.
- The sample-buffer subtitle preview renders, and Picture in Picture visibly opens.
- Diagnostic state confirmed `pip: true`, `picture.possible: true`, `layerStatus: 1`, and no layer error.
- iPhone Mirroring was active (`screenCaptured: true`). The broadcast picker did not present a chooser in that session. No broadcast extension process or app-audio frames were observed.

### Physical broadcast test — 22:49–22:51 CST

After disconnecting iPhone Mirroring, the user started Mimi Audio broadcast directly
on the phone. The extension process was observed alongside the host and separate
Mimi Audio Test app. The test app was brought forward with devicectl and the user
started its fixed English passage.

| Session elapsed | Received audio | Audio frames | Recognition updates | Translation updates |
| --- | --- | --- | --- | --- |
| 21 s | 5.34 s | 230 | 12 | 4 |
| 71 s | 55.06 s | 2,372 | 144 | 48 |
| 119 s | 103.06 s | 4,440 | 219 | 72 |

All three fresh diagnostic snapshots reported `running: true`, `pip: true`, no
recognition error, and no display-layer error. Counters continued increasing across
the 45-second recognition rotation intervals while the independent audio app was
foregrounded. The user reported the visible result appeared normal; no screenshot
was taken because mirroring would interfere with capture.

At 22:52 CST, after the user closed the PiP window, the saved state changed to
`running: false` and `pip: false` (4,979 audio frames / 115.57 audio seconds).
The broadcast extension process was no longer present, while the host remained
running. Closing PiP therefore stopped the receiving session and broadcast in this
run.

This verifies cross-app audio delivery, local recognition, successful translation
responses, and approximately two minutes of background subtitle operation for the
fixed fixture. It does **not** establish transcription/translation accuracy,
measured latency, arbitrary third-party or protected-media compatibility, or
long-duration reliability. Translation counters count successful responses, not
independent language-quality checks.

The `Documents/probe-status.json` file reports counters without storing transcript
text. It persists across launches, so a single saved file can be stale: verify live
processes and increasing session counters before interpreting it as current evidence.

Reference: Apple documents that screen recording and screen mirroring cannot be used at the same time:
https://support.apple.com/guide/iphone/take-a-screen-recording-iph52f6e1987/ios

The fixture is independently installed only for this test; its target is not a dependency of osu and it is not embedded in the osu app.
