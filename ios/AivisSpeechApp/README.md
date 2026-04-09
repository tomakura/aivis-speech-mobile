# AivisSpeechApp

This directory contains the real iOS app host for the `AivisSpeechiOS` package.

Run `ruby ../../tools/generate_ios_host_project.rb` from this directory, or
run the script from the repository root, to regenerate
`AivisSpeechApp.xcodeproj`.

Open `AivisSpeechApp.xcodeproj` in Xcode and run the `AivisSpeechApp` scheme on
an iOS simulator. Do not try to run `ios/AivisSpeechiOS/Package.swift`
directly on iOS.

If you build from a shell, prefer:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AivisSpeechApp.xcodeproj -scheme AivisSpeechApp -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' build
```
