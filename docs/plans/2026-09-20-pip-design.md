# Osu subtitle window

The user accepts iOS Picture in Picture as the current surface and wants it to
look elegant and recognizable. Keep the original video in its app, automatic
input to Chinese, and the new persistent option to show original text.

## Direction

Considered a large character beside the captions, a typography-only window,
and a compact character signature above the text. Use the compact signature:
it gives Osu a recognizable face while preserving the full caption width.

- Keep the existing 960 × 440 media canvas and system PiP controls.
- Flat near-black background, white main text, muted previous/original text.
  Character colors come only from the approved transparent brand asset.
- A small character and serif Osu wordmark sit at the top right. The previous
  sentence occupies the top left; a fine separator groups this context row.
- Left-align the current translation, with generous side margins and a medium
  weight. Hiding original text gives the main line more vertical space.
- Preserve the 360 ms eased sentence transition. Reduce Motion skips the
  transition. No perpetual decorative animation or new media session is needed.
- Empty, waiting and failure copy continues through the existing subtitle
  state. The mark is decorative; VoiceOver reads visible caption content.

## Implementation and acceptance

Update the shared CoreGraphics painter and package the existing mascot in the
host and isolated test app. Cache a downsampled image for frame rendering.
Production preview, video sample buffers and exported demonstration use the
same painter. Keep capture, provider and PiP lifecycle behavior unchanged.

Check short and long text with original shown/hidden at ordinary and maximum
accessibility sizes; inspect transitions and small rendered sizes. Check actual
Reduce Motion, incremental signed/device and simulator builds, and the settings
switch. Export a short authored-text clip for review. The current simulator
cannot establish physical PiP appearance, video coexistence or phone battery
behavior; those limits must stay explicit in the acceptance record.
