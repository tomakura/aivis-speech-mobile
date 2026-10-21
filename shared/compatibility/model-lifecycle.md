# AIVMX Model Lifecycle

mobile 版で固定するモデル状態:

- `installed`: `.aivmx` が端末上に存在する
- `loaded`: 推論ランタイムにロード済み
- `active`: 現在の話者選択や合成処理で利用中

## Allowed Transitions

1. `install -> installed`
2. `installed -> loaded`
3. `loaded -> active`
4. `active -> loaded`
5. `loaded -> installed`
6. `installed -> removed`

## Constraints

- `remove` の前に `active` / `loaded` を解除する
- メモリ警告時は `active` 以外の loaded model を LRU 順に unload 候補とする
- fixture では install 状態と loaded 状態を分離して表現する

