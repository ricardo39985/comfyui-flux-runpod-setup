# Workflows

Put exported ComfyUI workflow JSON files here.

Expected files:

```text
01_flux_krea_fresh_generation.json
02_flux_kontext_anchor_edit.json
03_flux_fill_masked_edit.json
```

The setup script copies any `*.json` files in this directory into:

```text
/workspace/runpod-slim/ComfyUI/user/default/workflows
```

Do not commit generated images, private reference images, or model files.
