# aivis-speech-mobile

Aivis Speech を iOS / Android で展開するためのクロスプラットフォーム向けモノレポです。

## Layout

```text
/
  ios/        iOS 先行実装
  android/    将来の Android 実装予約領域
  shared/     互換 schema / fixtures / docs
  vendor/     upstream 参照メモ
```

## Current Scope

- `ios/AivisSpeechApp`: 実際に Xcode で開いて起動する iOS app host
- `ios/AivisMobileCore`: Swift Package ベースの core 型・永続化・互換レイヤー
- `ios/AivisSpeechRuntime`: ONNX Runtime Mobile / CoreML EP を隔離する runtime 層
- `ios/AivisSpeechiOS`: app host から参照される SwiftUI package
- `shared/`: `.aisp` schema、desktop 互換 fixture、保存形式メモ
- `android/`: 将来の Gradle ルート用プレースホルダ

## Notes

- `furry.txt` は実装時のサブエージェント運用メモです。
- 現段階では Android の実装コードはまだ置かず、互換の前提だけを固定します。
- iOS で起動するときは `ios/AivisSpeechApp/AivisSpeechApp.xcodeproj` を開きます。
- `ios/AivisSpeechiOS/Package.swift` を iOS simulator 向けに直接 Run しないでください。
- shell から build する場合は `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付けるか、`xcode-select` を Xcode 本体へ向けてください。

## Runtime Assets

大きい runtime asset は Git に含めません。Git LFS も使いません。

- `ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources/BERTAssets/model_fp16.onnx`
  - 取得元: [tsukumijima/deberta-v2-large-japanese-char-wwm-onnx](https://huggingface.co/tsukumijima/deberta-v2-large-japanese-char-wwm-onnx)
- `ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources/OpenJTalkDictionary/*`
  - 取得元: [open_jtalk_dic_utf_8-1.11.tar.gz](https://downloads.sourceforge.net/open-jtalk/open_jtalk_dic_utf_8-1.11.tar.gz)

初回 clone 後、runtime を使う前に次を実行してください。

```bash
./tools/download_runtime_assets.sh
```

このスクリプトは次の場所へ必要ファイルを配置します。

- `ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources/BERTAssets/`
- `ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources/OpenJTalkDictionary/`

これらの生成ファイルは `.gitignore` 済みです。repo には commit しません。
