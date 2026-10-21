# AivisMobileCore

`AivisMobileCore` は mobile 版の core ドメイン層です。

初期段階で含めるもの:

- 推論・モデル・永続化の抽象プロトコル
- `.aisp` 互換の Codable 型
- 旧 project 形式からの最小 migration
- shared fixture を使った round-trip / 互換テスト

## Test

```bash
cd ios/AivisMobileCore
swift test
```

