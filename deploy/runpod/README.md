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

## Capture note

App-source edits found on the volume (inventory/coin narration guard and
duplicate auto-apply loot protection) were ported onto this branch's
`src/lib/dm/*` and tests. The volume still ran **0.39.1**; this fork was already
**0.40.2**, so the docker-export tree was not copied wholesale.
