# プリセット保存形式

プリセットは設定ファイル内の `presets` として保存する。

## 形式

```json
{
  "items": {
    "preset-key": {
      "name": "デフォルト：話者名",
      "speedScale": 1,
      "intonationScale": 1,
      "tempoDynamicsScale": 1,
      "pitchScale": 0,
      "volumeScale": 1,
      "pauseLengthScale": 1,
      "prePhonemeLength": 0.1,
      "postPhonemeLength": 0.1
    }
  },
  "keys": ["preset-key"]
}
```

## 補足

- `tempoDynamicsScale` は AivisSpeech 固有フィールド
- `morphingInfo` は必要なプリセットだけに付与する
- `keys` は表示順を表す
