# Lyrics-style subtitles

The user requested subtitles that appear like a lyrics app. Build on the working native subtitle window with a shorter 960 × 440 canvas: a dim previous translation, an emphasized current translation and the current original-language text below. Source and translation remain independently streamed; there is no claim of word-level synchronization or exact source/translation sentence alignment.

Preserve upstream utterance IDs. Partial revisions update in place; a new ID moves the previous line upward over 360 ms. Late events for old IDs cannot replace the current line. Hold only two visible lines and bounded retired IDs in memory; diagnostics continue to exclude subtitle text. Honor Reduce Motion. Render 30 fps only during the brief transition and retain 2 fps for steady PiP.

The phone has confirmed competition between Osu and another app's system PiP. Lyrics rendering does not remove that constraint. Keep the user's video in its original app and use the floating window for subtitles. Closing or replacing the subtitle window ends capture, preserves the last displayed text and explains the behavior. The public stop callback does not identify why it stopped, so do not claim to have detected the other app or auto-reclaim the window. Combining video and captions in one floating player would be separate product work.

Validation: native line-identity/late-event tests; cloud fixture identity delivery; simulator render, idle-media and restart checks; a fixed-text preview clip produced with the actual painter. Physical installation and new live PiP acceptance are reported separately.
