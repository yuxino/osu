# Dynamic Island subtitles

**Status:** the first implementation failed on a physical device — the broadcast
extension cannot look up a host-created activity, because `Activity.activities`
is process-scoped. The redesign lets the broadcast extension create and own its
own Live Activity, so no identifier crosses the process boundary. Independent
mode is re-enabled as an experimental feature; see [the failure, redesign and
simulator record](../acceptance/2026-09-25-island.md). The first design and its
checks below are retained as history.

## Redesign (extension-owned activity)

- When the authenticated configuration arrives, the ReplayKit extension requests
  its own activity, updates it per translated sentence, and ends it on every
  stop path. `IslandConfiguration` no longer carries an activity identifier.
- The host never creates an activity in island mode. It validates the credential
  and hands languages and the original-text preference to the extension after
  broadcast authentication.
- If the extension cannot create the activity (real-time activities disabled, or
  ActivityKit refusing a request from the extension sandbox), the broadcast ends
  immediately with guidance to switch to PiP.
- Apple documents updating a Live Activity from an app extension; starting one
  from a broadcast upload extension is undocumented. Whether `Activity.request`
  works there is exactly what device validation decides.
- Orphan risk: if the extension process dies without ending its activity, the
  host cannot see or end it. Content shows stale after 15 seconds and the system
  reclaims it on its own schedule.
- The simulator-side pre-broadcast block and the two-process lookup probe are
  retired: the design no longer depends on cross-process lookup, so the probe
  guards nothing.

## First design (superseded)

The requested mode shows translated app audio in Dynamic Island, with the current
sentence and optional original text in the expanded and Lock Screen presentations.
The existing monochrome interface and default PiP mode remain in use.

## Implementation

- Store the display preference separately from the speech engine. Apple local
  recognition uses PiP; the experimental island path currently supports Alibaba.
- Start ActivityKit in the foreground before opening the system broadcast picker.
  Embed a WidgetKit extension built from `native/widget/SubtitleWidget.swift` and
  the same `SubtitleActivityAttributes` definition used by the host and broadcast.
- After the broadcast authenticates over the existing loopback transport, send a
  single in-memory configuration containing its activity identifier, languages,
  original-text preference, and provider credential. Do not persist or log it.
- In island mode, the ReplayKit process owns the provider socket and subtitle
  updates. The host neither uploads a duplicate audio stream nor starts PiP.
  No silent-audio or hidden-PiP keepalive is added.
- Coalesce ActivityKit updates to at most once a second, refresh the stale deadline
  periodically, bound each text field to 600 UTF-8 bytes, and show stale status
  instead of implying that old content is still live.
- Closing the host connection, stopping broadcast, ending the activity, or provider
  failure stops the session. End the activity immediately to remove subtitle text.

## First-design validation boundary (superseded)

The SDK permits compiling ActivityKit into a broadcast extension. That alone does
not establish that the extension can discover and update a host-created activity
on a physical iPhone. The simulator fixture exercises the actual ActivityKit and
subtitle pipeline in one process with an in-memory provider, not this cross-process
boundary. Independent background operation must be checked on a trusted physical
device before treating this mode as accepted.

The signed test app was installed on 2026-09-25. Launch was rejected by the device
with a signature/profile-trust error. The existing signing team was preserved;
the app and both extensions have matching, unexpired development profiles.
The user must resolve the device's trust prompt before the remaining checks:

1. Start island mode and authorize Osu Audio; confirm `extension_attached` and
   a changing translation after leaving the host app for at least two minutes.
2. Verify compact, expanded, and Lock Screen layouts and the original-text option.
3. Stop from Osu and from the system broadcast controls; verify activity removal
   and provider socket closure. Repeat after network loss and activity dismissal.
4. Repeat an ordinary PiP session to check real-device parity.

Until those pass, README descriptions explicitly call the mode experimental.

Completed local checks:

- TypeScript, native core tests (including authenticated configuration rejection
  and Unicode payload bounds), Ruby syntax, and whitespace checks passed.
- Simulator app build and signed device build passed; both extensions are embedded.
- `--verify-island`: real ActivityKit subtitle/original updates, pause, and immediate
  cleanup passed with a synthetic provider and no network request.
- `--verify-capture-start`: existing 45-second permission wait, explicit retry,
  cancellation, authenticated first audio, and final cloud drain passed.
- `--verify-interactions`: existing home actions, credential error/retry/removal,
  and original-text synchronization passed.
- The final signed build was installed; installation is separate from launch and
  background acceptance, which remain unverified for the reasons above.
