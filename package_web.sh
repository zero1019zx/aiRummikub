#!/bin/bash
# 把导出的 Web 版打成 itch.io 可直接上传的 zip (index.html 在zip根目录)
set -e
cd "$(dirname "$0")/build/web"
if [ ! -f index.html ]; then
  echo "build/web/ 下没有 index.html — 请先在 Godot 中导出 Web 版本(导出路径用默认 index.html)"
  exit 1
fi
OUT="../rummi_web_$(date +%Y%m%d_%H%M).zip"
rm -f "$OUT"
zip -r -q "$OUT" .
echo "已打包: $(cd .. && pwd)/$(basename "$OUT")"
echo "上传 itch.io 时勾选 'This file will be played in the browser'"
