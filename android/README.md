# Android Workspace

`android/` は将来の Android 実装予約領域です。

現時点では実装を開始せず、以下だけを固定します。

- Gradle ルートとして展開できる構成を先に確保する
- iOS 専用 assumptions を Android 側へ持ち込まない
- `shared/` の schema / fixtures / compatibility docs を唯一の互換ソースとする

将来の候補:

- `app/`: Android アプリ本体
- `core/`: Kotlin 側ドメイン / 推論抽象
- `benchmark/`: 推論性能測定
- `androidTest/`: 端末上の互換性検証

