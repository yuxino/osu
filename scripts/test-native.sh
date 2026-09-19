#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p ios/native-tests
xcrun swiftc native/ios/DiagnosticStore.swift native/ios/LanguageRules.swift native/ios/AudioPacketDecoder.swift native/tests/core/main.swift -o ios/native-tests/core-tests
ios/native-tests/core-tests
