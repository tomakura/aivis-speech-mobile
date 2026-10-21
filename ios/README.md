# iOS Workspace

`ios/` は AivisSpeech Mobile の iOS 実装を置く領域です。

- `AivisSpeechApp/`: 実体のある iOS app host。Xcode ではこれを開く
- `AivisSpeechiOS/`: app host から参照する SwiftUI package
- `AivisMobileCore/`: 共通ドメイン、永続化、互換層、推論抽象
- `AivisSpeechRuntime/`: ONNX Runtime Mobile と CoreML EP の iOS runtime
- `AivisMobileTests/`: 将来の統合テスト
- `AivisMobileUITests/`: 将来の UI テスト

`AivisSpeechApp` は `tools/generate_ios_host_project.rb` で再生成できます。
`AivisSpeechiOS/Package.swift` は library として維持し、iOS app として直接 Run しません。
