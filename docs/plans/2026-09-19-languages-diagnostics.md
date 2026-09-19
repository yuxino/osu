# Device languages and local diagnostics

Keep ReplayKit, loopback PCM, on-device Speech and sample-buffer PiP. Enumerate
Speech locales at runtime; expose local-capable recognizers and explain unavailable
locales without enabling cloud fallback. Translation targets come from Apple's
supportedLanguages and each selected pair is checked for installed/supported/
unsupported. Offer transcription-only mode. Lock choices during a session and
invalidate asynchronous checks when the selection changes. iOS 18–25 supports
transcription only in this prototype; installed-session translation requires 26.

Persist a bounded diagnostic event journal with UUID, wall-clock timestamp, stage,
fixed event codes, sanitized error domain/code and numeric counters. Never write
transcripts, PCM, credentials or arbitrary error descriptions. Keep the existing
probe snapshot but timestamp it. Copy/export logs through native UI. Collect host
and extension journals separately when a trusted device is connected; disconnected
extensions cannot promise delivery to the host. Mark an unfinished previous host
session as interrupted/unknown on next launch rather than inferring a crash.

Verify pure rules/journal with executable Swift regression tests; compile device
and simulator native code, run an isolated simulator harness using production
controller and receiver. Simulator checks do not accept real ReplayKit capture,
local speech resources or translation quality. Finish with explicit physical tests.
