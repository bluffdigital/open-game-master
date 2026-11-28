# Runpod Open Game Master workspace

Captured from network volume `734bulubaz` (`/workspace`) on 2026-11-27.

These files are the host-side glue that runs beside the OGM app image on the
shared Runpod volume. They are **not** part of the Next.js app build.

## Layout on the volume

| Volume path | This folder |
|---|---|
| `/workspace/start_services.sh` | `start_services.sh` |
| `/workspace/install_ogm.sh` | `install_ogm.sh` |
| `/workspace/install.sh` | `install.sh` |
| `/workspace/ogm.env` | `ogm.env.example` (secrets redacted) |
| `/workspace/gm_model` | `gm_model` (active model profile name) |
| `/workspace/vllm-plugins/` | `vllm-plugins/` |
| `/workspace/chat-templates/` | `chat-templates/` |
| `/workspace/ogm-tests/` | `ogm-tests/` (ad-hoc vLLM probes) |

The app itself is exported from `lebbi/open-game-master:latest` into
`/workspace/ogm-image/app` by `install_ogm.sh` (via `crane`). Runtime data
(`data/*.sqlite*`, uploads, generated audio/images, HF/vLLM caches,
`node_modules`, `.next`) stays on the volume and is not tracked here.

## Model profiles

`gm_model` holds one of `qwen36` (default), `qwen36_27b`, or `llama33`.
`start_services.sh` reads it when starting vLLM.

| Profile | Serve target | Weights expectation |
|---|---|---|
| `qwen36` (default) | `Qwen/Qwen3.6-35B-A3B-FP8` with `HF_HUB_OFFLINE=1` | Already under `/workspace/hf` on the volume |
| `qwen36_27b` | `/root/qwen36-27b-fp8` | Container disk (falls back to `qwen36` if missing) |
| `llama33` | `/root/llama-awq` | Container disk (falls back to `qwen36` if missing) |

`install.sh` installs the vLLM venv and tooling only. It does **not** download
multi-GB checkpoints. Put default weights on the volume before relying on a
fresh pod with `HF_HUB_OFFLINE=1`. Older Qwen2.5 AWQ weights may remain in
`/workspace/hf` for rollback; they are not the default serve path.

## Capture note

Kept from the volume: `deploy/runpod/*` host glue and
`duplicateAppliedProblem` (auto-apply loot/coin replay protection on
`grant_item` / `modify_gold`). The volume’s inventory/coin **narration-guard**
port was **not** kept — it fought issue 1097’s `item-claims` / settle path
already on 0.40.2 (`test-items-change-hands`). The volume still ran **0.39.1**;
this fork was already **0.40.2**, so the docker-export tree was not copied
wholesale.
