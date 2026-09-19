# Osu mobile usability and acceptance

## Outcome

An everyday subtitle companion: open directly into language selection and readable subtitles, start listening with clear broadcast guidance, stop/restart without stale sessions, and receive complete final source/translation. Preserve neutral black/white/gray styling and device-local / explicit Alibaba choice. No unrelated phone operations this round.

## Decisions

Keep the native ReplayKit/PiP controller as the iOS screen; remove the extra demo landing tap. A React Native rewrite of the streaming screen would add bridge/state risk; a cosmetic reskin would leave diagnostic clutter and stop semantics unchanged. Main screen has language selectors, one subtitle surface, session state and start/stop. Service/key, downloads, synthetic test and diagnostics belong in a settings sheet. Use actual SF Symbols and accessible system typography, not emoji. Show cloud upload/cost disclosure before starting.

Implement session.finish after draining bounded queued audio. Stop capture immediately; use an eight-second deadline with one-second health checks for service completion, keep final subtitles, and allow immediate cancellation. Prevent new audio or a new session while draining. Synthetic tests require finalized source and translation, not merely draft updates. No automatic cloud retries.

## Acceptance

- Real Japanese cloud test yields complete source and Chinese final, then session.finished.
- Stop during connecting, transmitting and finishing; restart without old callbacks or extra uploads.
- Consecutive/longer playback continues; silence doesn't overwrite useful status.
- Background/PiP/broadcast flow and actual Safari/Bilibili capture tested in simulator where supported. Unsupported system behavior is a recorded gap, never replaced by synthetic evidence.
- Main page and settings visibly checked at normal and large text sizes; settings retain state, disabled controls explain missing resources, no demo/diagnostic clutter on home.
- Preserve Keychain credentials and no content diagnostics; compile full simulator and iPhone targets. Commit/push verified work and publish truthful preview evidence.
- Final goal remains open until cross-App acceptance and overall usable interaction are supported by evidence. Physical-device verification deferred under user's current scope.

Follow-up scope: the user subsequently authorized installing and launching the latest build on their connected phone for personal testing, and confirmed the app name Osu. Installation does not authorize the agent to start broadcasts or take over phone testing. Build 4 installation/startup is recorded in the acceptance document; cross-app behavior remains pending user testing.
