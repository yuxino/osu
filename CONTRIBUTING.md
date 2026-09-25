# Development

## Build for iPhone

Requires macOS, Node.js 22.13+, Xcode, Ruby/Bundler, and an Apple signing team.

```sh
git clone https://github.com/yuxino/osu.git
cd osu
npm ci
bundle install
npm run ios:prebuild
npm run ios:configure
cd ios
bundle exec pod install
cd ..
npm run ios:device
```

On the first build, select your development team for the app, broadcast extension, and OsuSubtitles widget extension in Xcode. `ios:device` creates a Release app with JavaScript bundled, so it runs without a development server. The native modules require a standalone app; Expo Go is not supported.

The deployment target is iOS 18. Apple on-device translation requires iOS 26; earlier versions can use supported local speech recognition without translation, or Alibaba mode.

## Native source and caches

- `native/ios/` is the maintained native source. `ios/` is generated and ignored; rerun `ios:configure` after prebuild.
- Always use `npm run ios:prebuild`, which passes `--no-clean`. Expo 57 otherwise clears the native directory and its build caches.
- `.build/` holds reusable build output and exported diagnostics outside the generated directory.
- `native/fixtures/` contains separate test apps, not shipped with Osu.

## Checks

```sh
npm run typecheck
scripts/test-native.sh
bundle exec ruby -c scripts/configure-ios-prototype.rb
git diff --check
```

In-app Alibaba sample tests use fixed synthetic Japanese audio and make real, billable provider requests. They do not test audio capture from another app. Simulator checks also cannot establish physical-device language support or background capture.

See the [Alibaba guide](docs/alibaba.md), [diagnostic and simulator checks](docs/languages-and-diagnostics.md), and [current device evidence](docs/acceptance/2026-09-19.md). The [initial prototype notes](docs/iphone-prototype.md) and older Flutter commits are retained as history.
