# Modern Mimi Flutter redesign

## Direction

Keep osu as a Flutter app and replace the 2019 interface and obsolete service
layer. The visual language combines warm stationery paper, deep ink, coral
controls, chartreuse highlights, and a cat-ear exchange mark. It should feel
playful and memorable without reducing the converter to a toy.

## Product scope

- Convert in either direction between 24 common currencies.
- Swap a pair without losing the converted amount.
- Search currencies in an accessible bottom sheet.
- Offer four common travel-pair shortcuts.
- Display the reference rate date, loading state, error state, and cached state.
- Support responsive Android, iOS, and Web layouts plus light/dark themes.

## Architecture

The UI is split into responsive page, input, picker, branding, and theme
widgets. Conversion parsing and formatting remain pure functions. A
`RateRepository` interface separates the page from the Frankfurter HTTPS API,
making widget tests deterministic. Successful quotes are stored with
`shared_preferences`; fresh quotes are reused for 24 hours and older quotes
remain available as an explicit offline fallback.

## Verification

- Unit tests cover parsing and formatting.
- Repository tests cover live response parsing, cache writes, stale fallback,
  and invalid data.
- Widget tests cover conversion, typing, swapping, searching, selection, and
  cached-state messaging.
- Static analysis, the full test suite, a release Web build, launcher-icon
  generation, and desktop/mobile visual review must pass before publishing.
