#!/usr/bin/env python3
"""把 build/web/ 打包成 itch.io 可直接上传的 zip: python3 package_web.py"""
import os
import zipfile

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(BASE, "build", "web")
OUT = os.path.join(BASE, "rummi_lite_web.zip")

if __name__ == "__main__":
    if not os.path.exists(os.path.join(ROOT, "index.html")):
        raise SystemExit("build/web/ 下没有 index.html — 请先在 Godot 中导出 Web 版本(入口名必须是 index.html)")
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, _dirs, files in os.walk(ROOT):
            for fn in files:
                p = os.path.join(dirpath, fn)
                z.write(p, os.path.relpath(p, ROOT))
    size_mb = os.path.getsize(OUT) / 1024 / 1024
    print(f"已生成 {OUT}  ({size_mb:.1f} MB)")
    print("itch.io 上传: 新建项目 → Kind of project 选 HTML → 上传此zip →")
    print("勾选 'This file will be played in the browser' → Embed 设 720x1280 +")
    print("勾选 Mobile friendly → Visibility 可选 Draft/Restricted(私密测试)")
