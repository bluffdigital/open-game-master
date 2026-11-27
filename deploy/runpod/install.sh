#!/bin/bash
# One-time installer for the A100 game-master pod. Everything persistent goes on /workspace.
export HF_HOME=/workspace/hf UV_PYTHON_INSTALL_DIR=/workspace/uv-python UV_CACHE_DIR=/workspace/.uv-cache UV_HTTP_TIMEOUT=300 UV_LINK_MODE=copy
L=/workspace/logs; mkdir -p $L /workspace/venvs /workspace/apt-cache
# apt deps (debs cached on /workspace so a restart can reinstall offline)
apt-get update -y > $L/apt.log 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dir::Cache::archives=/workspace/apt-cache espeak-ng espeak-ng-data libsndfile1 ffmpeg >> $L/apt.log 2>&1 && echo APT_DONE >> $L/apt.log
# ---- vLLM + model ----
(
set -e
uv venv --python /usr/bin/python3.12 /workspace/venvs/vllm
VIRTUAL_ENV=/workspace/venvs/vllm uv pip install vllm "huggingface_hub[cli]" hf_transfer
HF_HUB_ENABLE_HF_TRANSFER=1 /workspace/venvs/vllm/bin/hf download Qwen/Qwen2.5-32B-Instruct-AWQ
/workspace/venvs/vllm/bin/python -c 'import vllm;print("vllm",vllm.__version__)'
echo VLLM_INSTALL_DONE
) > $L/install_vllm.log 2>&1 &
# ---- ComfyUI + SDXL ----
(
set -e
cd /workspace
[ -d ComfyUI ] || git clone --depth 1 https://github.com/comfyanonymous/ComfyUI
uv venv --python /usr/bin/python3.12 /workspace/venvs/comfy
VIRTUAL_ENV=/workspace/venvs/comfy uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
VIRTUAL_ENV=/workspace/venvs/comfy uv pip install -r ComfyUI/requirements.txt
mkdir -p ComfyUI/models/checkpoints
[ -s ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors ] || curl -fL --retry 5 -o ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
ls -la ComfyUI/models/checkpoints
echo COMFY_INSTALL_DONE
) > $L/install_comfy.log 2>&1 &
# ---- Kokoro-FastAPI ----
(
set -e
until grep -q APT_DONE $L/apt.log; do sleep 5; done
mkdir -p /usr/share/espeak-ng-data && ln -sf /usr/lib/*/espeak-ng-data/* /usr/share/espeak-ng-data/ || true
cd /workspace
[ -d Kokoro-FastAPI ] || git clone --depth 1 https://github.com/remsky/Kokoro-FastAPI
cd Kokoro-FastAPI
uv venv --python 3.12
uv sync --frozen --extra gpu --no-install-project
.venv/bin/python docker/scripts/download_model.py --output api/src/models/v1_0
echo KOKORO_INSTALL_DONE
) > $L/install_kokoro.log 2>&1 &
# ---- Open Game Master (official image's /app, extracted without a Docker daemon) ----
(
set -e
cd /workspace
if [ ! -x /workspace/node/bin/node ]; then
  V=$(curl -s https://nodejs.org/dist/index.json | python3 -c 'import json,sys; print([r["version"] for r in json.load(sys.stdin) if r["version"].startswith("v22.")][0])')
  curl -fsSL https://nodejs.org/dist/$V/node-$V-linux-x64.tar.xz | tar -xJ -C /workspace && mv /workspace/node-$V-linux-x64 /workspace/node
fi
/workspace/node/bin/node --version
mkdir -p /workspace/tools && cd /workspace/tools
[ -x crane ] || curl -fsSL https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz | tar -xz crane
./crane digest lebbi/open-game-master:latest
mkdir -p /workspace/ogm-image
./crane export --platform linux/amd64 lebbi/open-game-master:latest - | tar -x -C /workspace/ogm-image app
ls /workspace/ogm-image/app
echo OGM_INSTALL_DONE
) > $L/install_ogm.log 2>&1 &
wait
echo ALL_INSTALL_DONE >> $L/install.log
