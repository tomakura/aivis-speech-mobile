# `.aisp` 保存形式

`.aisp` は AivisSpeech のプロジェクトファイルで、JSON 文字列として保存する。

## ルート

- `appVersion`: プロジェクト保存時のアプリバージョン
- `talk`: トーク領域の状態
- `song`: ソング領域の状態

## `talk`

- `audioKeys`: `audioItems` の参照順
- `audioItems`: 音声アイテム本体の辞書

各音声アイテムは少なくとも次を持つ。

- `text`
- `voice.engineId`
- `voice.speakerId`
- `voice.styleId`

任意で以下を持つ。

- `query`
- `presetKey`
- `morphingInfo`

## `song`

保存はするが、v1 の iOS 実装では UI 上の主要対象はトーク側とする。

- `tpqn`
- `tempos`
- `timeSignatures`
- `tracks`
- `trackOrder`

## 互換方針

- 既存 desktop の `.aisp` を読み込めることを前提にする
- 不明なプロパティは保存時に落とさない
- マイグレーションは `appVersion` を基準に行う
