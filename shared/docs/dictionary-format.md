# ユーザー辞書保存形式

ユーザー辞書は `word-uuid` をキーにした JSON オブジェクトとして保存する。

## 形式

```json
{
  "word-uuid": {
    "surface": "AivisSpeech",
    "priority": 5,
    "part_of_speech": "名詞",
    "part_of_speech_detail_1": "固有名詞",
    "part_of_speech_detail_2": "一般",
    "part_of_speech_detail_3": "*",
    "inflectional_type": "*",
    "inflectional_form": "*",
    "stem": "AivisSpeech",
    "yomi": "あいびすすぴーち",
    "pronunciation": "アイビススピーチ",
    "accent_type": 4,
    "accent_associative_rule": "auto"
  }
}
```

## 補足

- `snake_case` を基本形にする
- `UserDictWordForCompat` 相当の古い互換表現も読み込み側で受ける
- エクスポートは desktop と同じく JSON で行う
