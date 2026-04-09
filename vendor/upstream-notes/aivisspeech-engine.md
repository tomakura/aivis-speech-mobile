# AivisSpeech-Engine Upstream Notes

参照元:

- https://github.com/Aivis-Project/AivisSpeech-Engine

mobile 側で参照するポイント:

- `AudioQuery`, `AccentPhrase`, `Mora`, `Preset` の shape
- `AIVMX` モデル管理の概念
- Style-Bert-VITS2 ベースの推論前提
- model install / load / unload / update の API 役割

mobile 側で置き換えるポイント:

- Python / FastAPI 実装
- HTTP サーバーとしての起動
- desktop / server 向け process 管理
- CUDA / DirectML 前提の分岐
