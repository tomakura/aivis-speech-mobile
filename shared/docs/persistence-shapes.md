# Persistence Shapes

このドキュメントは mobile 版で固定する保存形式をまとめたものです。

## Project File

- 拡張子: `.aisp`
- 文字コード: UTF-8
- ベース: desktop AivisSpeech の project JSON
- talk セクションは desktop 互換を維持
- song セクションは schema 上保持し、v1 では積極実装しなくても round-trip を維持

## Preset Catalog

```json
{
  "items": {
    "preset-key": {
      "name": "Default",
      "speedScale": 1.0,
      "intonationScale": 1.0,
      "tempoDynamicsScale": 1.0,
      "pitchScale": 0.0,
      "volumeScale": 1.0,
      "pauseLengthScale": 1.0,
      "prePhonemeLength": 0.1,
      "postPhonemeLength": 0.1
    }
  },
  "keys": ["preset-key"]
}
```

## Default Style Registry

```json
[
  {
    "engineId": "engine-uuid",
    "speakerUuid": "speaker-uuid",
    "defaultStyleId": 888753760
  }
]
```

## Dictionary

mobile 版では desktop の「読み方＆アクセント辞書」と対応づく shape を先に固定する。

```json
{
  "entries": [
    {
      "id": "uuid",
      "surface": "琴葉",
      "pronunciation": "コトノハ",
      "accentType": 3,
      "wordType": "PROPER_NOUN",
      "priority": 5
    }
  ]
}
```

