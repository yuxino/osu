# Expo HAS CHANGED

Read the exact versioned docs at https://docs.expo.dev/versions/v57.0.0/ before writing any code.

Expo 57 prebuild defaults to clean. Always use `npm run ios:prebuild` (explicit `--no-clean`) to preserve the generated project and its build caches. Never run bare `expo prebuild` for incremental config or asset updates.

The product name is Osu. Mimi refers to the desktop reference implementation or stable internal module/data names; do not use it as the mobile app's display name. The broadcast extension display name is Osu Audio.

For signed device builds, leave CODE_SIGNING_ALLOWED unset so each target retains its own setting. A global YES incorrectly forces CocoaPods static libraries to sign. Reuse the existing team, app identifiers and build cache for device updates.
