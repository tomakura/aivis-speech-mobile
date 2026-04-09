# Compatibility

このディレクトリは desktop 互換と今後の mobile 互換に関する判断を置く。

## 方針

- desktop の `.aisp` を優先して読む
- 設定保存は desktop と同じキー名を使う
- 辞書とプリセットは JSON の形を変えない

## 現状メモ

- iOS 版は `AivisSpeech(GUI)` の機能等価を目標にする
- Android 版は同じ保存形式と fixture を再利用する
- 互換に影響する変更はここに追記する
