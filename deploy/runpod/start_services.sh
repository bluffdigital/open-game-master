#!/bin/bash
# Start (or restart missing) services on the A100 game-master pod. Safe to re-run.
# Usage: /workspace/start_services.sh [all|vllm|kokoro|ogm|comfyui|stop]
LOG=/workspace/logs
mkdir -p $LOG
export HF_HOME=/workspace/hf UV_PYTHON_INSTALL_DIR=/workspace/uv-python VLLM_CACHE_ROOT=/workspace/vllm-cache TRITON_CACHE_DIR=/workspace/triton-cache
up() { curl -s -o /dev/null -f -m 3 "$1"; }
ensure_apt() {
  # Container disk is wiped on restart: reinstall espeak-ng etc. from the debs cached on /workspace.
  command -v espeak-ng >/dev/null && return
  dpkg -i /workspace/apt-cache/*.deb >> $LOG/apt-restore.log 2>&1 || \
    { apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -o Dir::Cache::archives=/workspace/apt-cache espeak-ng espeak-ng-data libsndfile1 ffmpeg; } >> $LOG/apt-restore.log 2>&1
  mkdir -p /usr/share/espeak-ng-data && ln -sf /usr/lib/*/espeak-ng-data/* /usr/share/espeak-ng-data/ 2>/dev/null || true
}
start_kokoro() {
  up http://127.0.0.1:8880/health && { echo "kokoro already up"; return; }
  ensure_apt
  cd /workspace/Kokoro-FastAPI
  P=/workspace/Kokoro-FastAPI
  USE_GPU=true DEVICE=gpu PYTHONUNBUFFERED=1 PYTHONPATH=$P:$P/api MODEL_DIR=src/models VOICES_DIR=src/voices/v1_0 \
  WEB_PLAYER_PATH=$P/web PHONEMIZER_ESPEAK_PATH=/usr/bin PHONEMIZER_ESPEAK_DATA=/usr/share/espeak-ng-data ESPEAK_DATA_PATH=/usr/share/espeak-ng-data \
  setsid nohup $P/.venv/bin/uvicorn api.src.main:app --host 0.0.0.0 --port 8880 >> $LOG/kokoro.log 2>&1 < /dev/null &
  echo "kokoro starting"
}
start_vllm() {
  up http://127.0.0.1:8000/health && { echo "vllm already up"; return; }
  pgrep -f "vllm serve" >/dev/null && { echo "vllm still loading"; return; }
  # Qwen3.6-35B-A3B FP8 (~35 GB weights, Marlin W8A16 on A100) as game-master; the model Open Game Master is tuned for.
  # qwen3 reasoning parser + qwen3_coder tool parser per the Qwen model card. OGM asks for thinking on tool-deciding calls only.
  # Rollback: start_services.sh.bak-qwen25-* (Qwen2.5-32B-Instruct-AWQ weights are still in /workspace/hf).
  # Thinking cap: vLLM has no server-wide thinking budget, so the ASGI middleware /workspace/vllm-plugins/ogm_think_budget.py adds thinking_token_budget (OGM_THINKING_TOKEN_BUDGET) to thinking requests. Pre-change copy: start_services.sh.bak-qwen36-prebudget-*
  # Model profile (2026-11-26): /workspace/gm_model holds "qwen36" (default, 35B-A3B), "qwen36_27b" or "llama33".
  # Switch: echo llama33 > /workspace/gm_model && /workspace/start_services.sh restart-vllm   (back: echo qwen36 ...)
  GM_MODEL=$(cat /workspace/gm_model 2>/dev/null || echo qwen36)
  if [ "$GM_MODEL" = "qwen36_27b" ] && [ ! -f /root/qwen36-27b-fp8/config.json ]; then
    echo "qwen36_27b weights missing from /root/qwen36-27b-fp8 (container disk is wiped on restart); using qwen36"; GM_MODEL=qwen36
  fi
  if [ "$GM_MODEL" = "llama33" ] && [ ! -f /root/llama-awq/config.json ]; then
    echo "llama33 weights missing from /root/llama-awq (container disk is wiped on restart); using qwen36"; GM_MODEL=qwen36
  fi
  if [ "$GM_MODEL" = "qwen36_27b" ]; then
  # Qwen3.6-27B-FP8 (dense, ~31 GB) on the container disk at /root/qwen36-27b-fp8. Same parsers, template, think budget and
  # flags as qwen36 (35B-A3B); native FP8 on H100.
  HF_HUB_OFFLINE=1 PYTHONPATH=/workspace/vllm-plugins OGM_THINKING_TOKEN_BUDGET=2048 setsid nohup /workspace/venvs/vllm/bin/vllm serve /root/qwen36-27b-fp8 \
    --host 0.0.0.0 --port 8000 --served-model-name game-master \
    --enable-prefix-caching --max-model-len 65536 --language-model-only \
    --gpu-memory-utilization 0.68 --max-num-seqs 8 \
    --reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder \
    --chat-template /workspace/chat-templates/qwen36-ogm.jinja --middleware ogm_think_budget.ThinkBudget --reasoning-config '{"reasoning_end_str": "\n\nI have thought enough; time to act on it.\n</think>\n\n"}' \
    >> $LOG/vllm.log 2>&1 < /dev/null &
  elif [ "$GM_MODEL" = "llama33" ]; then
  # Llama-3.3-70B-Instruct AWQ INT4 (casperhansen/llama-3.3-70b-instruct-awq), weights on the container disk at /root/llama-awq.
  # No reasoning parser; OGM_THINKING_TOKEN_BUDGET=0 makes the middleware skip the thinking budget (repetition guard stays).
  HF_HUB_OFFLINE=1 PYTHONPATH=/workspace/vllm-plugins OGM_THINKING_TOKEN_BUDGET=0 setsid nohup /workspace/venvs/vllm/bin/vllm serve /root/llama-awq \
    --host 0.0.0.0 --port 8000 --served-model-name game-master \
    --enable-prefix-caching --max-model-len 65536 \
    --gpu-memory-utilization 0.80 --max-num-seqs 4 \
    --enable-auto-tool-choice --tool-call-parser llama3_json \
    --chat-template /workspace/chat-templates/llama33-ogm.jinja --middleware ogm_think_budget.ThinkBudget \
    >> $LOG/vllm.log 2>&1 < /dev/null &
  else
  HF_HUB_OFFLINE=1 PYTHONPATH=/workspace/vllm-plugins OGM_THINKING_TOKEN_BUDGET=2048 setsid nohup /workspace/venvs/vllm/bin/vllm serve Qwen/Qwen3.6-35B-A3B-FP8 \
    --host 0.0.0.0 --port 8000 --served-model-name game-master \
    --enable-prefix-caching --max-model-len 65536 --language-model-only \
    --gpu-memory-utilization 0.68 --max-num-seqs 8 \
    --reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder \
    --chat-template /workspace/chat-templates/qwen36-ogm.jinja --middleware ogm_think_budget.ThinkBudget --reasoning-config '{"reasoning_end_str": "\n\nI have thought enough; time to act on it.\n</think>\n\n"}' \
    >> $LOG/vllm.log 2>&1 < /dev/null &
  fi
  echo "vllm starting"
}
start_comfyui() {
  up http://127.0.0.1:8188/system_stats && { echo "comfyui already up"; return; }
  cd /workspace/ComfyUI
  PYTHONUNBUFFERED=1 setsid nohup /workspace/venvs/comfy/bin/python main.py --listen 0.0.0.0 --port 8188 \
    >> $LOG/comfyui.log 2>&1 < /dev/null &
  echo "comfyui starting"
}
start_ogm() {
  up http://127.0.0.1:3005/api/health && { echo "ogm already up"; return; }
  [ -e /app ] || ln -s /workspace/ogm-image/app /app
  cd /workspace/ogm-image/app
  mkdir -p data public/uploads public/generated public/generated-audio logs models/speech
  [ -f /workspace/ogm.env ] && { set -a; . /workspace/ogm.env; set +a; }
  KEY_FILE=data/.db-key
  if [ -z "$DB_ENCRYPTION_KEY" ]; then
    [ -f $KEY_FILE ] || { /workspace/node/bin/node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex'))" > $KEY_FILE; chmod 600 $KEY_FILE; }
    export DB_ENCRYPTION_KEY=$(cat $KEY_FILE)
  fi
  NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 HOSTNAME=0.0.0.0 PORT=3005 \
  CONTENT_DB_PATH=/workspace/ogm-image/app/content/open5e.sqlite \
  setsid nohup /workspace/node/bin/node server.js >> $LOG/ogm.log 2>&1 < /dev/null &
  echo "ogm starting"
}
restart_vllm() { pkill -f "[v]llm serve"; for i in $(seq 1 30); do pgrep -f "[v]llm serve" >/dev/null || break; sleep 1; done; pkill -9 -f "[v]llm serve"; sleep 2; start_vllm; }
stop_all() { pkill -f "vllm serve"; pkill -f "uvicorn api.src.main:app"; pkill -f "ComfyUI/main.py|main.py --listen"; pkill -f "node server.js"; echo stopped; }
echo "=== $(date) start_services.sh ${1:-all}"
case "${1:-all}" in
  restart-vllm) restart_vllm;;
  kokoro) start_kokoro;; vllm) start_vllm;; ogm) start_ogm;; comfyui) start_comfyui;; stop) stop_all;;
  all)
    # Kokoro first (small), then vLLM must claim its GPU share before ComfyUI loads SDXL.
    start_kokoro; start_ogm; start_vllm
    for i in $(seq 1 120); do up http://127.0.0.1:8000/health && break; sleep 5; done
    start_comfyui;;
esac
