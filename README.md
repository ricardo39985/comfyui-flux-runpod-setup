# ComfyUI Flux RunPod Setup

Reusable setup script for a disposable RunPod ComfyUI image-generation pod.

This repo is for the image-only Flux stack:

- `FLUX.1 Krea dev` for fresh generation
- `FLUX.1 Kontext dev` for anchor/reference edits
- `FLUX.1 Fill dev` for masked edits / inpainting

No model files, tokens, generated images, or personal reference images should be committed to this repo.

## Tested pod shape

- RunPod template: `ComfyUI - CUDA 12.8`
- GPU: A40 48GB or RTX A6000 48GB
- ComfyUI path: `/workspace/runpod-slim/ComfyUI`
- Disposable storage pattern: use a volume disk during the pod session, then terminate the pod when done

## Hugging Face access required

Before running the script, make sure your Hugging Face account has accepted access/terms for the gated Black Forest Labs models used here.

Required downloads:

| Purpose | Repo | File | Primary destination |
|---|---|---|---|
| CLIP-L text encoder | `comfyanonymous/flux_text_encoders` | `clip_l.safetensors` | `models/text_encoders/clip_l.safetensors` |
| T5XXL FP16 text encoder | `comfyanonymous/flux_text_encoders` | `t5xxl_fp16.safetensors` | `models/text_encoders/t5xxl_fp16.safetensors` |
| Flux VAE | `black-forest-labs/FLUX.1-schnell` | `ae.safetensors` | `models/vae/ae.safetensors` |
| Krea generator | `black-forest-labs/FLUX.1-Krea-dev` | `flux1-krea-dev.safetensors` | `models/diffusion_models/flux1-krea-dev.safetensors` |
| Kontext editor | `Comfy-Org/flux1-kontext-dev_ComfyUI` | `split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors` | `models/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors` |
| Fill inpainting | `black-forest-labs/FLUX.1-Fill-dev` | `flux1-fill-dev.safetensors` | `models/diffusion_models/flux1-fill-dev.safetensors` |

## Compatibility paths

ComfyUI workflow JSONs can contain both active loader values and separate embedded `properties.models` metadata. The missing-model popup may check that metadata even when the loader dropdown is already set correctly.

For that reason, `setup_flux_stack.sh` creates compatibility aliases so both the workflow loaders and missing-model checks resolve cleanly:

```text
models/text_encoders/t5/t5xxl_fp16.safetensors
models/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors
models/vae/FLUX1/ae.safetensors
models/diffusion_models/flux1-krea-dev_fp8_scaled.safetensors
```

These aliases point back to the full installed files and avoid unnecessary duplicate downloads.

## Usage on a fresh RunPod pod

Open the RunPod web terminal, then run:

```bash
cd /workspace/runpod-slim
git clone https://github.com/ricardo39985/comfyui-flux-runpod-setup.git
cd comfyui-flux-runpod-setup
bash setup_flux_stack.sh
```

If Hugging Face auth is needed, the script will prompt for a token with hidden input.

You can also provide a token for the current shell session:

```bash
export HF_TOKEN=hf_your_read_token_here
bash setup_flux_stack.sh
```

Do not commit the token to the repo.

## Workflow JSONs

The script copies JSON files found in `workflows/` into:

```text
/workspace/runpod-slim/ComfyUI/user/default/workflows
```

Included workflow files:

```text
workflows/01_flux_krea_fresh_generation.json
workflows/02_flux_kontext_anchor_edit.json
workflows/03_flux_fill_masked_edit.json
```

After running the script, refresh ComfyUI and load the workflows from the copied workflow directory or directly from the repo.

## Safety rules for this repo

Never commit:

- Hugging Face tokens
- RunPod credentials
- model files such as `.safetensors`, `.ckpt`, `.gguf`
- generated images
- private identity references
- outfit/reference photos
- LoRA training datasets

Keep this repo limited to setup code, README docs, and reusable workflow JSONs.
