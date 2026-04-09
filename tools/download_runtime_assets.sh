#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_RESOURCES_DIR="$ROOT_DIR/ios/AivisSpeechRuntime/Sources/AivisSpeechRuntime/Resources"
BERT_DIR="$RUNTIME_RESOURCES_DIR/BERTAssets"
OPENJTALK_DIR="$RUNTIME_RESOURCES_DIR/OpenJTalkDictionary"

BERT_MODEL_URL="https://huggingface.co/tsukumijima/deberta-v2-large-japanese-char-wwm-onnx/resolve/main/model_fp16.onnx"
BERT_TOKENIZER_URL="https://huggingface.co/tsukumijima/deberta-v2-large-japanese-char-wwm-onnx/resolve/main/tokenizer.json"
OPENJTALK_DICT_URL="https://downloads.sourceforge.net/open-jtalk/open_jtalk_dic_utf_8-1.11.tar.gz"

mkdir -p "$BERT_DIR" "$OPENJTALK_DIR"

download_file() {
  local url="$1"
  local destination="$2"
  if [[ -f "$destination" ]]; then
    echo "skip: $destination"
    return
  fi
  echo "download: $destination"
  curl -L --fail --retry 3 --retry-delay 2 -o "$destination" "$url"
}

download_file "$BERT_MODEL_URL" "$BERT_DIR/model_fp16.onnx"
download_file "$BERT_TOKENIZER_URL" "$BERT_DIR/tokenizer.json"

if [[ ! -f "$OPENJTALK_DIR/sys.dic" ]]; then
  archive_path="$(mktemp -t openjtalk-dic.XXXXXX.tar.gz)"
  extract_dir="$(mktemp -d -t openjtalk-dic.XXXXXX)"
  trap 'rm -f "$archive_path"; rm -rf "$extract_dir"' EXIT

  echo "download: $archive_path"
  curl -L --fail --retry 3 --retry-delay 2 -o "$archive_path" "$OPENJTALK_DICT_URL"
  tar -xzf "$archive_path" -C "$extract_dir"

  extracted_root="$(find "$extract_dir" -maxdepth 1 -type d -name 'open_jtalk_dic_utf_8-*' | head -n 1)"
  if [[ -z "$extracted_root" ]]; then
    echo "failed: could not find extracted OpenJTalk dictionary" >&2
    exit 1
  fi

  cp "$extracted_root"/{char.bin,left-id.def,matrix.bin,pos-id.def,rewrite.def,right-id.def,sys.dic,unk.dic,COPYING} "$OPENJTALK_DIR"/
  echo "installed: $OPENJTALK_DIR"
fi
