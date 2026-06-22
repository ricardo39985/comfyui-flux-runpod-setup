#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n=== %s ===\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

find_comfy() {
  if [[ -n "${COMFY:-}" && -d "${COMFY}" ]]; then printf '%s\n' "$COMFY"; return 0; fi
  if [[ -d "/workspace/runpod-slim/ComfyUI" ]]; then printf '%s\n' "/workspace/runpod-slim/ComfyUI"; return 0; fi
  local found
  found="$(find /workspace -maxdepth 4 -type d -name ComfyUI 2>/dev/null | head -n 1 || true)"
  [[ -n "$found" ]] && { printf '%s\n' "$found"; return 0; }
  die "ComfyUI directory not found. Set COMFY=/path/to/ComfyUI and rerun."
}

COMFY="$(find_comfy)"
log "Flux ComfyUI setup"
echo "Repo dir:   $REPO_DIR"
echo "ComfyUI:    $COMFY"
cd "$COMFY"

ensure_hf_cli() {
  if command -v hf >/dev/null 2>&1; then return 0; fi
  if command -v python3 >/dev/null 2>&1; then
    log "Installing Hugging Face CLI"
    python3 -m pip install -U "huggingface_hub[cli]"
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
  command -v hf >/dev/null 2>&1 || die "hf CLI not found. Use a ComfyUI RunPod template with hf installed, or install huggingface_hub."
}

hf_authed() { hf auth whoami >/dev/null 2>&1; }

ensure_hf_auth() {
  if hf_authed; then
    log "Hugging Face auth detected"
    hf auth whoami || true
    return 0
  fi

  if [[ -n "${HF_TOKEN:-}" ]]; then
    log "Checking HF_TOKEN from environment"
    if HF_TOKEN="$HF_TOKEN" hf auth whoami >/dev/null 2>&1; then
      echo "HF_TOKEN is valid."
      return 0
    fi
  fi

  log "Hugging Face token required"
  echo "Missing gated Hugging Face models were detected."
  echo "Create a read-only token at Hugging Face, accept the BFL model terms, then paste it here."
  echo "Input is hidden. The token is not written to this repo."
  read -r -s -p "HF token: " HF_TOKEN_INPUT
  echo
  [[ -n "$HF_TOKEN_INPUT" ]] || die "No token provided."
  export HF_TOKEN="$HF_TOKEN_INPUT"

  if HF_TOKEN="$HF_TOKEN" hf auth whoami >/dev/null 2>&1; then
    echo "HF_TOKEN is valid."
    return 0
  fi

  if hf auth login --token "$HF_TOKEN" --add-to-git-credential false >/dev/null 2>&1; then
    echo "Hugging Face login succeeded."
    return 0
  fi

  die "Hugging Face auth failed. Check token and accepted model terms."
}

mkdir -p models/text_encoders/t5 models/vae/FLUX1 models/diffusion_models models/loras models/controlnet

file_size_mb() { du -m "$1" | cut -f1; }
file_ok() { local path="$1" min_mb="$2"; [[ -f "$path" ]] && [[ "$(file_size_mb "$path")" -ge "$min_mb" ]]; }

link_or_copy() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || return 0
  [[ -e "$dest" ]] && return 0
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest" 2>/dev/null || cp -f "$src" "$dest"
}

create_compatibility_links() {
  # ComfyUI workflow JSONs contain two sources of truth:
  # 1) loader widget values, and 2) embedded properties.models metadata used by
  # missing-model checks. These links satisfy both without forcing duplicate downloads.
  link_or_copy "$COMFY/models/text_encoders/t5/t5xxl_fp16.safetensors" "$COMFY/models/text_encoders/t5xxl_fp16.safetensors"
  link_or_copy "$COMFY/models/text_encoders/t5xxl_fp16.safetensors" "$COMFY/models/text_encoders/t5/t5xxl_fp16.safetensors"
  link_or_copy "$COMFY/models/text_encoders/t5xxl_fp16.safetensors" "$COMFY/models/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors"
  link_or_copy "$COMFY/models/vae/FLUX1/ae.safetensors" "$COMFY/models/vae/ae.safetensors"
  link_or_copy "$COMFY/models/vae/ae.safetensors" "$COMFY/models/vae/FLUX1/ae.safetensors"
  link_or_copy "$COMFY/models/diffusion_models/flux1-krea-dev.safetensors" "$COMFY/models/diffusion_models/flux1-krea-dev_fp8_scaled.safetensors"
}

create_compatibility_links

missing_required() {
  local missing=0
  file_ok models/text_encoders/clip_l.safetensors 200 || missing=1
  file_ok models/text_encoders/t5xxl_fp16.safetensors 9000 || missing=1
  file_ok models/vae/ae.safetensors 250 || missing=1
  file_ok models/diffusion_models/flux1-krea-dev.safetensors 20000 || missing=1
  file_ok models/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors 8000 || missing=1
  file_ok models/diffusion_models/flux1-fill-dev.safetensors 20000 || missing=1
  [[ "$missing" -eq 1 ]]
}

ensure_hf_cli
missing_required && ensure_hf_auth || log "All required model files already appear to be present"

download_file() {
  local label="$1" repo="$2" file="$3" dest_dir="$4" final_path="$5" min_mb="$6"
  if file_ok "$final_path" "$min_mb"; then
    echo "SKIP    $label"
    echo "        $final_path ($(du -h "$final_path" | cut -f1))"
    return 0
  fi
  [[ -f "$final_path" ]] && { echo "REMOVE  incomplete/small file: $final_path"; rm -f "$final_path"; }
  echo "DOWNLOAD $label"
  echo "        repo: $repo"
  echo "        file: $file"
  mkdir -p "$dest_dir"
  hf download "$repo" "$file" --local-dir "$dest_dir"
}

download_kontext() {
  local final_path="models/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors"
  if file_ok "$final_path" 8000; then
    echo "SKIP    FLUX.1 Kontext dev FP8"
    echo "        $final_path ($(du -h "$final_path" | cut -f1))"
    return 0
  fi
  [[ -f "$final_path" ]] && { echo "REMOVE  incomplete/small file: $final_path"; rm -f "$final_path"; }
  echo "DOWNLOAD FLUX.1 Kontext dev FP8"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  hf download "Comfy-Org/flux1-kontext-dev_ComfyUI" "split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors" --local-dir "$tmp_dir"
  mkdir -p models/diffusion_models
  mv "$tmp_dir/split_files/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors" "$final_path"
  rm -rf "$tmp_dir"
}

log "Downloading missing model files"
download_file "CLIP-L text encoder" "comfyanonymous/flux_text_encoders" "clip_l.safetensors" "models/text_encoders" "models/text_encoders/clip_l.safetensors" 200
download_file "T5XXL FP16 text encoder" "comfyanonymous/flux_text_encoders" "t5xxl_fp16.safetensors" "models/text_encoders" "models/text_encoders/t5xxl_fp16.safetensors" 9000
download_file "Flux VAE ae.safetensors" "black-forest-labs/FLUX.1-schnell" "ae.safetensors" "models/vae" "models/vae/ae.safetensors" 250
download_file "FLUX.1 Krea dev" "black-forest-labs/FLUX.1-Krea-dev" "flux1-krea-dev.safetensors" "models/diffusion_models" "models/diffusion_models/flux1-krea-dev.safetensors" 20000
download_kontext
download_file "FLUX.1 Fill dev" "black-forest-labs/FLUX.1-Fill-dev" "flux1-fill-dev.safetensors" "models/diffusion_models" "models/diffusion_models/flux1-fill-dev.safetensors" 20000

create_compatibility_links

log "Verifying required files"
check_file() {
  local label="$1" path="$2" min_mb="$3"
  if file_ok "$path" "$min_mb"; then
    echo "OK      $label"
    echo "        $path ($(du -h "$path" | cut -f1))"
  elif [[ -f "$path" ]]; then
    echo "SMALL   $label"
    echo "        $path ($(du -h "$path" | cut -f1)) -- may be incomplete"
    return 1
  else
    echo "MISSING $label"
    echo "        expected at: $path"
    return 1
  fi
}

check_file "CLIP-L text encoder" models/text_encoders/clip_l.safetensors 200
check_file "T5XXL FP16 text encoder" models/text_encoders/t5xxl_fp16.safetensors 9000
check_file "T5XXL FP16 compatibility path" models/text_encoders/t5/t5xxl_fp16.safetensors 9000
check_file "T5XXL FP8 compatibility alias" models/text_encoders/t5xxl_fp8_e4m3fn_scaled.safetensors 9000
check_file "Flux VAE ae.safetensors" models/vae/ae.safetensors 250
check_file "Flux VAE compatibility path" models/vae/FLUX1/ae.safetensors 250
check_file "FLUX.1 Krea dev" models/diffusion_models/flux1-krea-dev.safetensors 20000
check_file "FLUX.1 Krea compatibility alias" models/diffusion_models/flux1-krea-dev_fp8_scaled.safetensors 20000
check_file "FLUX.1 Kontext dev FP8" models/diffusion_models/flux1-dev-kontext_fp8_scaled.safetensors 8000
check_file "FLUX.1 Fill dev" models/diffusion_models/flux1-fill-dev.safetensors 20000

log "Installing saved workflows if present"
if compgen -G "$REPO_DIR/workflows/*.json" >/dev/null; then
  mkdir -p "$COMFY/user/default/workflows"
  cp -fv "$REPO_DIR"/workflows/*.json "$COMFY/user/default/workflows/"
  echo "Workflows copied to: $COMFY/user/default/workflows"
else
  echo "No workflow JSON files found in: $REPO_DIR/workflows"
  echo "Add exported ComfyUI workflows there later."
fi

log "Disk usage"
du -sh models || true
df -h /workspace || true

log "DONE"
echo "Flux image stack installed and verified."
echo "Open ComfyUI, refresh the browser, then load workflows from the repo or user/default/workflows."
