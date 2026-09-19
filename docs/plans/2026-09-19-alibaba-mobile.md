# Alibaba LiveTranslate on iPhone

Port Mimi's existing low-latency LiveTranslate wire contract to Swift, retaining
ReplayKit/16 kHz mono Int16 PCM and PiP. Keep Apple local mode as a separate choice.
Use the same fixed Beijing DashScope endpoint, model and session.update shape;
source choices auto/zh/en/ja/ko and translated targets zh/en/ja match Mimi's current
catalog. Original-only remains in Apple mode for this iteration; Audio 3.0,
Qwen-MT quality/Turbo and full desktop profile management are not part of this port.

Cloud mode explicitly uploads selected App audio to Alibaba and uses the user's
billable key. Keychain only, write-only UI, no source/env/plaintext fallbacks. Do
not copy the desktop key silently. No video/mic, recording or content diagnostics.
Cloud mode never depends on Apple's Speech authorization or language downloads.

Use bounded audio buffering, readiness ACK before sending, setup/send/pong
timeouts, generation cancellation and bounded response text. Stop immediately
closes transport and discards pending content. Do not retry billable sessions
silently. Server drafts replace previews; finals prevent later drafts for the
same item from overwriting them. Source and translation are separate latest
streams, not a durable synchronized transcript/history.

Test exact protocol and queue behavior offline, run a simulator fake-transport
smoke through the production client, then build the complete app and iPhone target.
Without a user-configured credential, do not claim Alibaba recognition succeeded.
Cloud inference removes the Apple model restriction but does not establish that
ReplayKit can capture Safari audio in a simulator; that remains a separate check.
