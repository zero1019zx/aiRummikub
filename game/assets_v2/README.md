# Rummi Lite Premium Visual Assets v2

This folder is the higher-fidelity pass. It keeps the engineering structure from `assets/`, but the core card, button, badge, and board materials come from image-generated source sheets instead of code-drawn primitives.

## Pipeline

1. Source sheets live in `source_sheets/`.
2. `tools/v2/build_premium_assets.py` removes the chroma background, crops separated elements, and composites exact numbers/Chinese text.
3. `tools/v2/make_preview_scene_v2.py` builds an integration preview.
4. `tools/v2/make_contact_sheet_v2.py` builds a browsable sheet.
5. `tools/v2/verify_assets_v2.py` checks required files, PNG validity, card dimensions, and manifest coverage.

## Why This Exists

The first pass in `assets/` is structurally useful but too programmatic. This v2 pass prioritizes the painterly bevels, gold rims, soft shadows, and tactile mobile-game material quality from the original references.

## Commands

```bash
python3 tools/v2/build_premium_assets.py
python3 tools/v2/make_preview_scene_v2.py
python3 tools/v2/make_contact_sheet_v2.py
python3 tools/v2/verify_assets_v2.py
```
