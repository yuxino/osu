#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/native-tests
xcrun swiftc native/ios/DiagnosticStore.swift native/ios/LanguageRules.swift native/ios/AudioPacketDecoder.swift native/ios/AlibabaProtocol.swift native/ios/CaptureReadiness.swift native/ios/PCMBacklog.swift native/ios/LyricTrack.swift native/tests/core/main.swift -o .build/native-tests/core-tests
.build/native-tests/core-tests
