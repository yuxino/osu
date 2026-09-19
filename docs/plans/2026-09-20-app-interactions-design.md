# Osu app interactions

The home screen should make starting, reading and stopping a session obvious. Keep the existing neutral palette, serif wordmark and approved character.

## Selected flow

- Pin the brand/settings header and main action. Scroll language choices and subtitle preview between them. Keep a direct original-text toggle beside the preview.
- Tapping **开始听** prepares the local receiver and opens the iOS broadcast picker directly. Remove the app-owned permission guide. The system's **开始广播** confirmation remains required.
- Before authenticated broadcast, keep cloud and media inactive. Cancelling the system panel leaves a retryable home state with an explicit Cancel action. Returning to the app must not reopen a dismissed panel automatically.
- Start becomes Stop once connected. Finishing disables the primary action, preserves the last subtitle, and provides a separate force-finish action.
- First-use cloud setup opens a dedicated credential editor. Validate locally, keep errors beside the field, preserve input after a failed save, and confirm removal. Save means stored locally, not server-verified.

## Alternatives

Keeping the guide preserves the extra tap the user explicitly rejected. Placing the unstyled circular system control on the home screen splits one operation across two controls. Forwarding the primary action to an attached public `RPSystemBroadcastPickerView` keeps one app action while retaining system consent. If its embedded control is unavailable, show a retryable error; do not silently start capture or use private selectors.

## Verification

Check actual simulator presentation/cancellation of the system panel separately from fixtures. Use injected picker and credential operations to test waiting, retry, foreground, failed-save recovery, cancel and removal without touching the user's key. Re-run authenticated transport and final-result lifecycle regressions. Inspect normal and accessibility layouts, build both targets, and install only on the simulator. Physical ReplayKit/PiP acceptance remains separate.
