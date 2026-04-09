# AivisSpeechRuntime

This package contains the iOS runtime layer for `AivisSpeechMobile`.

- `AivisMobileCore` remains the contract layer.
- `AivisSpeechRuntime` owns ONNX Runtime integration.
- `AivisSpeechiOS` stays focused on UI and state presentation.

## Asset setup

Large runtime assets are not committed to Git.

- BERT ONNX: `Resources/BERTAssets/model_fp16.onnx`
- OpenJTalk dictionary: `Resources/OpenJTalkDictionary/*`

From the repo root, download them with:

```bash
./tools/download_runtime_assets.sh
```
