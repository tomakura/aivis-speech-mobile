# デフォルトスタイル保存形式

デフォルトスタイルは設定ファイル内の `defaultStyleIds` として保存する。

## 形式

```json
[
  {
    "engineId": "engine-uuid",
    "speakerUuid": "speaker-uuid",
    "defaultStyleId": 1234
  }
]
```

## 補足

- `speakerUuid` 単位で 1 件持つ
- `engineId` は元話者を一意に辿るために保持する
- 初回導入時は話者ごとの先頭スタイルを既定値にできる
